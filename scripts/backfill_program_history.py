#!/usr/bin/env python
"""Seed program history from what is left of the data, then attribute what we can.

History can only start now. `src/db.py save_user_program` upserts one row per
athlete, so every program that has already been replaced is gone — this cannot
recover them. What it can do:

  1. archive each athlete's CURRENT stored program, with its interval running
     from the program's own start date so it owns its already-elapsed weeks;
  2. set `session_uid` on existing `workout_matches` rows, using the workout's
     own date to decide which planned session the program-relative key meant;
  3. set `session_uid` on existing `session_logs` rows, using `completed_at`.

Attribution is unambiguous-only. A row whose key matches more than one candidate
on that date, or none, is left NULL and keeps working through the legacy path.
Notably it does NOT try to infer a start date from (workout.date, session_key):
`start = date - (week_number - 1) * 7 - day_index` is wrong by
(week_number - 1 - week_index) * 7 days, which for a program numbered from its
absolute week is a fifteen-week error, and it is undefined when a week_number
repeats. Guessing there would fabricate plans that never existed.

Idempotent and re-runnable.

    python scripts/backfill_program_history.py --dry-run
    python scripts/backfill_program_history.py
    python scripts/backfill_program_history.py --user <user_id>

Run AFTER migrations/005_program_history.sql and BEFORE 006_session_log_scope.sql
— 006 moves the session_logs primary key onto the uid this fills in.
"""
from __future__ import annotations

import argparse
import os
import sys
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

from src import program_history as ph          # noqa: E402  (needs DATABASE_URL first)
from src.db import new_conn                    # noqa: E402


def archive_current_programs(cur, users: list[str], dry_run: bool) -> dict:
    """Put each athlete's stored program at the head of their timeline."""
    stats = {'archived': 0, 'already': 0, 'skipped': 0}
    for user_id in users:
        cur.execute('SELECT program_data FROM user_programs WHERE user_id = %s', (user_id,))
        row = cur.fetchone()
        envelope = row[0] if row else None
        if not isinstance(envelope, dict):
            stats['skipped'] += 1
            continue
        if not ph.start_date_of(envelope):
            print(f'  {user_id}: no start date — cannot be placed on a timeline')
            stats['skipped'] += 1
            continue
        if dry_run:
            vid = ph.version_id(user_id, envelope)
            rows = len(ph.flatten_program(vid, envelope))
            print(f'  {user_id}: would archive {vid[:12]}… ({rows} planned sessions)')
            stats['archived'] += 1
            continue
        out = ph.record_version(user_id, envelope, source='backfill')
        if out['recorded']:
            print(f"  {user_id}: archived {str(out['versionId'])[:12]}…")
            stats['archived'] += 1
        elif out['reason'] == 'already_active':
            stats['already'] += 1
        else:
            print(f"  {user_id}: skipped ({out['reason']})")
            stats['skipped'] += 1
    return stats


def attribute_matches(cur, users: list[str], dry_run: bool) -> dict:
    """Give existing matches the uid of the session they actually referred to."""
    stats = {'set': 0, 'ambiguous': 0}
    for user_id in users:
        cur.execute('''
            SELECT m.imported_workout_id, m.session_key, w.date
              FROM workout_matches m
              LEFT JOIN workouts w ON w.id = m.imported_workout_id
                                  AND w.user_id = m.user_id
             WHERE m.user_id = %s AND m.session_uid IS NULL
               AND m.session_key <> '' AND m.match_confidence <> 'rejected'
        ''', (user_id,))
        for workout_id, session_key, workout_date in cur.fetchall():
            if not workout_date:
                stats['ambiguous'] += 1
                continue
            planned = ph.resolve_session(user_id, legacy_key=session_key,
                                         date_str=str(workout_date))
            if not planned:
                stats['ambiguous'] += 1
                continue
            if not dry_run:
                cur.execute('UPDATE workout_matches SET session_uid = %s '
                            'WHERE user_id = %s AND imported_workout_id = %s',
                            (planned['session_uid'], user_id, workout_id))
            stats['set'] += 1
    return stats


def attribute_logs(cur, users: list[str], dry_run: bool) -> dict:
    """Same for session logs, dated by completed_at.

    Skips a row whose target key is already taken. Two rows can point at one
    session — the day-level '3-Monday' and the indexed '3-Monday-0' — and
    migrations/006 makes COALESCE(session_uid, session_key) the primary key, so
    giving both the same uid would collide. Those want merging by hand; this
    reports them rather than guessing which set data to keep.
    """
    stats = {'set': 0, 'undated': 0, 'ambiguous': 0, 'would_collide': 0}
    for user_id in users:
        cur.execute('SELECT session_key, completed_at FROM session_logs '
                    'WHERE user_id = %s AND session_uid IS NULL', (user_id,))
        rows = cur.fetchall()
        claimed: set[str] = set()
        cur.execute('SELECT session_uid FROM session_logs WHERE user_id = %s '
                    'AND session_uid IS NOT NULL', (user_id,))
        claimed.update(r[0] for r in cur.fetchall())

        for session_key, completed_at in rows:
            if not completed_at:
                stats['undated'] += 1
                continue
            planned = ph.resolve_session(user_id, legacy_key=session_key,
                                         date_str=str(completed_at)[:10])
            if not planned:
                stats['ambiguous'] += 1
                continue
            uid = planned['session_uid']
            if uid in claimed:
                print(f'  {user_id}: {session_key} and another row both point at '
                      f'{uid[:20]}… — left alone, merge by hand')
                stats['would_collide'] += 1
                continue
            if not dry_run:
                cur.execute('UPDATE session_logs SET session_uid = %s '
                            'WHERE user_id = %s AND session_key = %s',
                            (uid, user_id, session_key))
            claimed.add(uid)
            stats['set'] += 1
    return stats


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run', action='store_true',
                        help='report what would change and write nothing')
    parser.add_argument('--user', help='one user id instead of everyone')
    args = parser.parse_args()

    conn = new_conn(autocommit=False)
    if conn is None:
        print('ERROR: could not connect')
        return 1

    try:
        with conn.cursor() as cur:
            if args.user:
                users = [args.user]
            else:
                cur.execute('SELECT DISTINCT user_id FROM user_programs ORDER BY user_id')
                users = [r[0] for r in cur.fetchall()]
            print(f'{len(users)} athlete(s)' + (' — DRY RUN' if args.dry_run else ''))

            print('\n1. archiving current programs')
            archived = archive_current_programs(cur, users, args.dry_run)
            print(f"   archived {archived['archived']}, already present "
                  f"{archived['already']}, skipped {archived['skipped']}")

            # The steps below read back what step 1 wrote, through their own
            # connections, so it has to be visible first.
            if not args.dry_run:
                conn.commit()

            print('\n2. attributing workout matches')
            matches = attribute_matches(cur, users, args.dry_run)
            print(f"   set {matches['set']}, left alone {matches['ambiguous']}")

            print('\n3. attributing session logs')
            logs = attribute_logs(cur, users, args.dry_run)
            print(f"   set {logs['set']}, undated {logs['undated']}, "
                  f"left alone {logs['ambiguous']}, need merging {logs['would_collide']}")

        if args.dry_run:
            conn.rollback()
            print('\nDRY RUN — nothing written')
        else:
            conn.commit()
            print('\nDone.')
        return 0
    except Exception as e:
        conn.rollback()
        print(f'\nFAILED, rolled back: {e}')
        return 1
    finally:
        conn.close()


if __name__ == '__main__':
    sys.exit(main())
