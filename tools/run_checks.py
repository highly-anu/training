#!/usr/bin/env python
"""Run the Python checks (checks/python_suites.yaml) on a commit, safely.

The pre-push hook calls this (checks.sh). Every suite runs in a clean checkout
of the commit, made for the run outside the repository and removed after it:
- no `.env` or `.env.local` reaches it. A suite run from the main checkout
  loads `.env.local`, which points the database at training_test, the local
  dev database; one run from a .claude/worktrees/ worktree walks up to the
  production `.env`. The database and Supabase variables are blanked as well.
- it tests what is being pushed, not what the working tree holds.
- nothing a suite writes (an output file, a throwaway package) lands in a
  working tree.

The three suites that drop tables each get a database of their own, created and
dropped here; without a local Postgres they are skipped, never run on their
default. The gitignored data/*.fit fixtures are copied in from the main
checkout.

    .venv/bin/python tools/run_checks.py                 # every suite, on HEAD
    .venv/bin/python tools/run_checks.py --rev <sha>     # on that commit
    .venv/bin/python tools/run_checks.py --only test_selection.py tools/check_styles.py
    .venv/bin/python tools/run_checks.py --garmin        # also the Garmin release build
    .venv/bin/python tools/run_checks.py --list          # the registry, checked

Exits 1 when a suite fails, or when a test_*.py at the root is in no section
of the registry (a new test cannot be forgotten).
"""
from __future__ import annotations

import argparse
import glob
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REGISTRY = os.path.join(ROOT, 'checks', 'python_suites.yaml')
TIMEOUT = 1500  # seconds per suite
TAIL = 40
DEV_DB = 'training_test'
GREEN, RED, DIM, OFF = ('\033[32m', '\033[31m', '\033[2m', '\033[0m') if sys.stdout.isatty() else ('',) * 4


def registry(path: str = REGISTRY) -> dict:
    with open(path, encoding='utf-8') as fh:
        doc = yaml.safe_load(fh)
    return {'suites': doc.get('suites') or [], 'exclusive': doc.get('exclusive') or [],
            'scratch_db': doc.get('scratch_db') or [], 'never': doc.get('never') or {}}


def commands(reg: dict) -> list[str]:
    """Every command the registry runs, in its order."""
    return reg['suites'] + reg['exclusive'] + reg['scratch_db']


def registry_problems(reg: dict, root: str = ROOT) -> list[str]:
    out = []
    listed = {shlex.split(c)[0] for c in commands(reg)} | set(reg['never'])
    for script in sorted({shlex.split(c)[0] for c in commands(reg)}):
        if not os.path.exists(os.path.join(root, script)):
            out.append(f'{script} is listed but does not exist')
    for path in sorted(glob.glob(os.path.join(root, 'test_*.py'))):
        name = os.path.basename(path)
        if name not in listed:
            out.append(f'{name} is in no section of checks/python_suites.yaml: list it, or put it under never with why')
    seen: set = set()
    for c in commands(reg):
        if c in seen:
            out.append(f'{c} is listed twice')
        seen.add(c)
    return out


def _git(*args, cwd=ROOT) -> str:
    return subprocess.run(['git', *args], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


def _main_checkout() -> str:
    """The repository's main checkout (where the gitignored fixtures live)."""
    common = _git('rev-parse', '--path-format=absolute', '--git-common-dir')
    return os.path.dirname(common)


def _postgres() -> bool:
    return shutil.which('pg_isready') is not None and subprocess.run(
        ['pg_isready', '-q', '-h', 'localhost'], capture_output=True).returncode == 0


def _clean_env() -> dict:
    env = {k: v for k, v in os.environ.items() if not k.startswith(('CHECKS_', 'GIT_'))}
    env.update({'DATABASE_URL': '', 'SUPABASE_URL': '', 'SUPABASE_SERVICE_ROLE_KEY': '',
                'SUPABASE_ANON_KEY': '', 'AUTHORING_ENABLED': '', 'PYTHONDONTWRITEBYTECODE': '1'})
    env.pop('TEST_DATABASE_URL', None)
    return env


def _run(cmd: str, cwd: str, env: dict) -> tuple[str, int, float, str]:
    start = time.time()
    try:
        p = subprocess.run([sys.executable, *shlex.split(cmd)], cwd=cwd, env=env, capture_output=True,
                           text=True, timeout=TIMEOUT, stdin=subprocess.DEVNULL)
        rc, out = p.returncode, (p.stdout or '') + (p.stderr or '')
    except subprocess.TimeoutExpired as e:
        rc, out = 124, f'timed out after {TIMEOUT} s\n' + (e.stdout or b'').decode(errors='replace')[-4000:]
    return cmd, rc, time.time() - start, out


def _report(cmd: str, rc: int, secs: float, out: str) -> None:
    if rc == 0:
        print(f'  {cmd} {GREEN}✓{OFF} {DIM}({secs:.0f}s){OFF}', flush=True)
    else:
        print(f'  {cmd} {RED}✗ exit {rc}{OFF} {DIM}({secs:.0f}s){OFF}', flush=True)
        for line in out.rstrip().splitlines()[-TAIL:]:
            print(f'      {line}')


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--rev', default='HEAD', help='the commit to check (default HEAD)')
    ap.add_argument('--only', nargs='+', help='run these registry commands only')
    ap.add_argument('--garmin', action='store_true', help='also build the Garmin app for every device (--release)')
    ap.add_argument('--jobs', type=int, default=max(2, (os.cpu_count() or 4) - 2))
    ap.add_argument('--list', action='store_true', help='print the registry and check it; run nothing')
    args = ap.parse_args()

    if args.list:
        reg = registry()
        for section in ('suites', 'exclusive', 'scratch_db'):
            print(f'{section}:'); [print(f'  {c}') for c in reg[section]]
        print('never:'); [print(f'  {k}: {v}') for k, v in reg['never'].items()]
        problems = registry_problems(reg)
        for p in problems:
            print(f'{RED}registry:{OFF} {p}')
        return 1 if problems else 0

    rev = _git('rev-parse', args.rev)
    base = tempfile.mkdtemp(prefix='training-checks-')
    checkout = os.path.join(base, 'training')
    _git('worktree', 'add', '--detach', '--quiet', checkout, rev)
    created_dbs: list[str] = []
    failed: list[str] = []
    try:
        # The commit's own list, held to the commit's own tests: a branch that
        # adds a test lists it in the same change.
        own = os.path.join(checkout, 'checks', 'python_suites.yaml')
        reg = registry(own if os.path.exists(own) else REGISTRY)
        problems = registry_problems(reg, checkout)
        for p in problems:
            print(f'{RED}registry:{OFF} {p}')
        wanted = set(args.only or commands(reg))
        unknown = wanted - set(commands(reg))
        if unknown:
            print(f'{RED}not in the registry:{OFF} {", ".join(sorted(unknown))}')
        if problems or unknown:
            return 1
        main = _main_checkout()
        for fit in glob.glob(os.path.join(main, 'data', '*.fit')):
            shutil.copy(fit, os.path.join(checkout, 'data'))
        env = _clean_env()
        if _postgres() and not env.get('TEST_ADMIN_DSN'):
            # The suites that make their own database connect as `postgres` by
            # default, a role a Homebrew Postgres does not have: their SQL half
            # then skips. The current user is the server's superuser there.
            env['TEST_ADMIN_DSN'] = 'postgresql://localhost:5432/postgres?sslmode=disable'
        print(f'python checks on {rev[:9]} in a clean checkout ({args.jobs} at a time)', flush=True)

        def run_all(cmds, jobs, env_for=lambda c: env):
            with ThreadPoolExecutor(max_workers=jobs) as pool:
                for result in pool.map(lambda c: _run(c, checkout, env_for(c)), cmds):
                    _report(*result)
                    if result[1] != 0:
                        failed.append(result[0])

        run_all([c for c in reg['suites'] if c in wanted], args.jobs)

        scratch = [c for c in reg['scratch_db'] if c in wanted]
        if scratch:
            if not _postgres():
                for c in scratch:
                    print(f'  {c} {DIM}– skipped: no local Postgres (never run on its default, {DEV_DB}){OFF}')
            else:
                urls = {}
                for i, c in enumerate(scratch):
                    name = f'training_checks_{os.getpid()}_{i}'
                    subprocess.run(['createdb', '-h', 'localhost', name], check=True, capture_output=True)
                    created_dbs.append(name)
                    urls[c] = f'postgresql://localhost:5432/{name}?sslmode=disable'
                    assert DEV_DB not in urls[c]
                run_all(scratch, args.jobs, lambda c: {**env, 'TEST_DATABASE_URL': urls[c]})

        run_all([c for c in reg['exclusive'] if c in wanted], 1)

        if args.garmin:
            build = os.path.join(checkout, 'garmin', 'TrainingCompanionCIQ', 'build.sh')
            sdk = os.environ.get('CIQ_SDK') or glob.glob(os.path.expanduser(
                '~/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-*'))
            key = os.environ.get('CIQ_KEY') or os.path.expanduser('~/.garmin-keys/developer_key')
            if not sdk or not os.path.exists(key):
                print(f'  garmin build {DIM}– skipped: no Connect IQ SDK or developer key on this machine{OFF}')
            else:
                start = time.time()
                p = subprocess.run(['bash', build, '--release'], cwd=os.path.dirname(build), env=env,
                                   capture_output=True, text=True, stdin=subprocess.DEVNULL)
                _report('garmin build.sh --release', p.returncode, time.time() - start, p.stdout + p.stderr)
                if p.returncode:
                    failed.append('garmin build')
    finally:
        for name in created_dbs:
            subprocess.run(['dropdb', '-h', 'localhost', '--if-exists', name], capture_output=True)
        subprocess.run(['git', 'worktree', 'remove', '--force', checkout], cwd=ROOT, capture_output=True)
        shutil.rmtree(base, ignore_errors=True)
    if failed:
        print(f'{RED}{len(failed)} failed:{OFF} {", ".join(failed)}')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
