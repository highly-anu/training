#!/usr/bin/env python
"""Put back the elapsed days a regenerate rewrote, so the block carries on.

Before the clients kept the days already behind the athlete, "from tomorrow"
(and the injury, schedule and equipment regenerates) replaced the whole week
the tail started in. The sessions done and matched earlier that week left the
plan; their matches stayed on the old version's uids and fell off the current
program, and the week's adherence with them.

This takes each date before the cutoff whose sessions the current program
plans differently from the version that was in force on that date, and gives
it back that version's sessions — only from a version of the same block (same
start date), never from an earlier program. Then it saves the program, which
bumps the revision so a client holding the old copy reloads, and records it:
with the past restored, program_history.record_version sees the block
continue, takes over its earlier intervals and moves their matches, suggestions
and logs onto the current program (`carry_over_until`).

Dry run unless --apply. Back up first (scripts/backup_prod.sh).

    python scripts/restore_elapsed_days.py --user <user_id>
    python scripts/restore_elapsed_days.py --user <user_id> --apply
    python scripts/restore_elapsed_days.py --user <user_id> --before 2026-10-18
"""
from __future__ import annotations

import argparse
import os
import sys
from datetime import date, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

if not os.environ.get('DATABASE_URL'):
    print('ERROR: DATABASE_URL is not set')
    sys.exit(1)

from src import program_history as ph                       # noqa: E402
from src.db import get_user_program, save_user_program, get_program_revision  # noqa: E402


def describe(sessions) -> str:
    if not sessions:
        return 'rest'
    return ', '.join(f"{s.get('modality')}/{(s.get('archetype') or {}).get('id')} "
                     f"({(s.get('archetype') or {}).get('name')})" for s in sessions)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--user', required=True)
    ap.add_argument('--before', help='restore dates before this (YYYY-MM-DD); default tomorrow')
    ap.add_argument('--apply', action='store_true', help='save and record; default is a dry run')
    args = ap.parse_args()

    cutoff = date.fromisoformat(args.before) if args.before else date.today() + timedelta(days=1)
    envelope = get_user_program(args.user)
    start = ph.start_date_of(envelope or {})
    if not start:
        print('no stored program with a start date')
        return 1
    restored, changed = ph.restore_elapsed(args.user, envelope, cutoff)

    print(f'program starts {start}; restoring dates before {cutoff}')
    if not changed:
        print('nothing to restore: every elapsed day is as it was planned')
        return 0
    for d, wi, day, now, was, vid in changed:
        print(f'  {d} (week index {wi}, {day}): {describe(now)}  ->  {describe(was)}   [from {vid}]')

    if not args.apply:
        print('\ndry run — pass --apply to save')
        return 0

    for key in ('revision', 'programVersionId', 'historyRecorded'):
        restored.pop(key, None)
    save_user_program(args.user, restored)
    revision = get_program_revision(args.user)
    out = ph.record_version(args.user, restored, source='repair', source_revision=revision)
    print(f"\nsaved (revision {revision}); history: {out['reason']}, "
          f"{out.get('carried', 0)} row(s) carried onto {out['versionId']}")
    return 0 if out['reason'] in ('continued', 'already_active') else 2


if __name__ == '__main__':
    sys.exit(main())
