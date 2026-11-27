#!/bin/bash
# Deploy the API to Fly from this Mac, the steps of .github/workflows/deploy-api.yml
# without GitHub Actions. The fallback for when GitHub starts no run; the normal
# path is the workflow (a push to master, or `gh workflow run deploy-api.yml`).
#
#   scripts/deploy_api.sh              # deploy origin/master
#   scripts/deploy_api.sh <commit>     # deploy another commit (a rollback)
#   scripts/deploy_api.sh --check      # say what would be deployed, deploy nothing
#
# It deploys a clean export of the commit, never the working tree, so nothing
# uncommitted and no .env reaches the image. Needs a signed-in flyctl
# (`fly auth login`).
set -euo pipefail

APP=training-api
WORKFLOW=deploy-api.yml

check=0
rev=origin/master
for arg in "$@"; do
  case "$arg" in
    --check) check=1 ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) rev="$arg" ;;
  esac
done

cd "$(git rev-parse --show-toplevel)"

fly=$(command -v flyctl || command -v fly) || { echo "flyctl is not installed" >&2; exit 1; }
"$fly" auth whoami >/dev/null 2>&1 || {
  echo "flyctl is not signed in. Run: fly auth login" >&2; exit 1; }

git fetch --quiet origin
sha=$(git rev-parse --verify --quiet "$rev^{commit}") || { echo "no such commit: $rev" >&2; exit 1; }
echo "Deploying $(git log -1 --format='%h %s' "$sha")"

# Two deploys at once fight over the machines' lease (2026-10-31: production
# ran on three machines). Never start beside a run of the workflow.
if command -v gh >/dev/null 2>&1; then
  busy=$(
    for s in in_progress queued waiting pending requested; do
      gh run list --workflow "$WORKFLOW" --status "$s" --json databaseId --jq '.[].databaseId' 2>/dev/null || true
    done
  )
  if [ -n "$busy" ]; then
    echo "A Deploy API run is in flight on GitHub (run $(echo $busy)). Wait for it." >&2
    exit 1
  fi
else
  echo "gh is not installed: cannot see whether GitHub is deploying. Check Actions first." >&2
fi

if [ "$check" -eq 1 ]; then
  echo "--check: nothing deployed."
  exit 0
fi

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
git archive "$sha" | tar -x -C "$dir"

# --ha=false: a deploy that finds no machine launches one, not one and a spare.
(cd "$dir" && "$fly" deploy --remote-only --ha=false --image-label "local-${sha:0:12}")

n=$("$fly" machines list -a "$APP" -q | grep -c . || true)
if [ "$n" -ne 1 ]; then
  echo "$APP runs on $n machines, not 1. Run: fly scale count 1 -a $APP" >&2
  exit 1
fi
echo "Deployed ${sha:0:12}; $APP runs on one machine."
