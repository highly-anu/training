# Local checks run by the shared git hooks in ../code-checks (see its README).
# They replace the GitHub workflows (Training contracts, Frontend Build) that
# ran until 2026-10-26. Bypass once: --no-verify.
#
#   ../code-checks/try.sh pre-push            # what a push of this branch would run
#   ../code-checks/try.sh pre-push --all      # every area, whatever changed
#
# The Python checks are one list, checks/python_suites.yaml, run by
# tools/run_checks.py in a clean checkout of the pushed commit (no .env, a
# scratch database for the suites that drop tables). Each area is gated on the
# paths it owns.

# The repository's virtualenv lives in the main checkout; a .claude/worktrees/
# worktree has none, and the system Python lacks the dependencies.
checks_python() {
  local main
  main="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
  if [ -n "$CHECKS_PYTHON" ]; then PY="$CHECKS_PYTHON"
  elif [ -x .venv/bin/python ]; then PY=.venv/bin/python
  elif [ -x "$main/.venv/bin/python" ]; then PY="$main/.venv/bin/python"
  else find_python || return 1
  fi
}

# The commit being pushed (the first ref that is not a deletion), else HEAD.
pushed_rev() {
  local rev
  rev=$(push_refs | awk '$2 !~ /^0+$/ { print $2; exit }')
  echo "${rev:-HEAD}"
}

frontend_ready() {
  [ -d frontend/node_modules ] || (cd frontend && npm ci --silent)
}

# What changes what:
#   backend  — the engine, data, schemas, API, tools, tests, migrations: every Python check
#   frontend — the web app, and the JSON the browser's matcher and zones read
#   ios      — the apps, and the watch-day fixture WatchDayTests decodes
#   garmin   — the watch app, its vocabulary and fixtures, a package's watch.yaml
BACKEND='^(src/|data/|docs/schemas/|docs/package-fidelity/|tools/|checks/|migrations/|test_packages/|scripts/[^/]*\.py$|test_[^/]*\.py$|fixture_packages\.py$|api\.py$|oauth\.py$|mcp_server\.py$|requirements\.txt$|checks\.sh$)'
FRONTEND='^frontend/|^data/(matching_rules|matcher_fixtures)\.json$|^data/commons/hr_zones\.json$'
IOS='^ios/|^data/watch_day_fixture\.json$'
GARMIN='^garmin/|^data/commons/watch_vocabulary\.json$|^data/watch_fixtures\.json$|/watch\.yaml$'

# Fast, every commit: syntax of the changed Python, and each changed YAML
# file of the data against its schema. The secret scan runs for every project.
pre_commit() {
  step py-syntax py_compile_changed
  local yaml
  yaml=$(changed_files | grep -E '^data/.*\.ya?ml$' | while read -r f; do [ -f "$f" ] && echo "$f"; done)
  if [ -n "$yaml" ]; then
    # shellcheck disable=SC2086
    checks_python && step yaml-schema "$PY" tools/validate_entities.py -q $yaml
  fi
}

pre_push() {
  local rev only=""
  rev=$(pushed_rev)
  checks_python || { step python "false"; return 0; }

  if touched "$BACKEND"; then
    if touched "$GARMIN"; then
      step_live python "$PY" tools/run_checks.py --rev "$rev" --garmin
    else
      step_live python "$PY" tools/run_checks.py --rev "$rev"
    fi
  else
    # Code that must not name a package, outside the backend.
    touched '^frontend/src/|^ios/|^garmin/' && only="tools/check_code_neutral.py"
    touched "$GARMIN" && only="$only test_watch_spec.py"
    if [ -n "$only" ]; then
      # shellcheck disable=SC2086
      step_live python "$PY" tools/run_checks.py --rev "$rev" --only $only $(touched "$GARMIN" && echo --garmin)
    else
      skip python "no backend changes"
    fi
  fi

  if touched "$FRONTEND"; then
    if frontend_ready; then
      step frontend-lint npm_in frontend run lint
      step frontend-build npm_in frontend run build      # tsc -b, then vite build
      step frontend-test npm_in frontend test            # vitest: the contrast guard, the TS matcher parity
    else
      step frontend-install false
    fi
  else
    skip frontend "no frontend changes"
  fi

  if touched "$IOS"; then
    if command -v xcodebuild >/dev/null 2>&1; then
      step_live ios-tests ./ios/run_tests.sh
    else
      skip ios-tests "no Xcode on this machine"
    fi
  else
    skip ios-tests "no iOS changes"
  fi

  # The Garmin core's (:test) functions run in the open Connect IQ simulator
  # (build.sh --test), which a hook must never drive: run them by hand.
  touched "$GARMIN" && skip garmin-core-tests "run by hand: garmin/TrainingCompanionCIQ/build.sh --test"
  return 0
}
