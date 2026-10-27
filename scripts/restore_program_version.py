#!/usr/bin/env python
"""Put an archived program back in force, undoing a save that replaced it.

On 2026-10-27 the web's "From tomorrow onwards" saved a whole new 16-week
program starting tomorrow over a block two weeks in: the Program Settings
sheet's start-date field had re-anchored the program in memory, so "tomorrow"
fell in week 1 and nothing was kept. The block's matches, suggestions and logs
stayed where they were, on the replaced version's sessions — only the program
in force and the timeline moved. This undoes exactly that:

  * the stored program becomes the archived version's envelope again (the
    save bumps the revision, so a client holding the other copy reloads);
  * the replacing activation is closed empty (effective_to = effective_from),
    kept on the timeline as the record that the plan changed;
  * the version's own activation is reopened (effective_to = NULL), so it owns
    its dates again — the only column the timeline ever updates.

It refuses unless the version to restore holds the activation that the open
one closed, and nothing — a match, a suggestion, a log, a result — points at
the open version's sessions yet: undoing it would orphan them.

Dry run unless --apply. Back up first (scripts/backup_prod.sh).

    python scripts/restore_program_version.py --user <user_id> --version <version_id>
    python scripts/restore_program_version.py --user <user_id> --version <version_id> --apply
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

from src import program_history as ph                                      # noqa: E402
from src.db import get_program_revision, get_user_program, new_conn, save_user_program  # noqa: E402

# Every table that names a planned session by its uid.
REFERENCING = ('workout_matches', 'workout_match_suggestions', 'session_logs',
               'standard_result_suggestions', 'performance_logs')


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--user', required=True)
    ap.add_argument('--version', required=True, help='the program_versions id to put back')
    ap.add_argument('--apply', action='store_true', help='save and record; default is a dry run')
    args = ap.parse_args()

    conn = new_conn(autocommit=False)
    if conn is None:
        print('no database connection')
        return 1
    try:
        with ph._dict_cursor(conn) as cur:
            cur.execute('SELECT pg_advisory_xact_lock(hashtext(%s))', ('program_history:' + args.user,))
            cur.execute('SELECT program_data, start_date, week_count FROM program_versions '
                        'WHERE user_id = %s AND id = %s', (args.user, args.version))
            version = cur.fetchone()
            if version is None:
                print(f'no version {args.version} for {args.user}')
                return 1
            cur.execute('''SELECT id, program_version_id, effective_from, effective_to
                             FROM program_activations WHERE user_id = %s
                         ORDER BY id DESC''', (args.user,))
            acts = cur.fetchall()
            open_act = next((a for a in acts if a['effective_to'] is None), None)
            if open_act is None or open_act['program_version_id'] == args.version:
                print('nothing to undo: the version is already in force (or nothing is)')
                return 0
            # The version's own interval must be the one the open activation closed.
            own = next((a for a in acts if a['program_version_id'] == args.version
                        and a['id'] != open_act['id']), None)
            if own is None or own['effective_to'] != max(own['effective_from'], open_act['effective_from']):
                print(f'refusing: {args.version} is not the activation that '
                      f'{open_act["program_version_id"]} replaced')
                return 1
            prefix = open_act['program_version_id'] + ':%'
            referenced = {}
            for table in REFERENCING:
                cur.execute(f'SELECT COUNT(*) AS n FROM {table} '
                            f'WHERE user_id = %s AND session_uid LIKE %s', (args.user, prefix))
                n = cur.fetchone()['n']
                if n:
                    referenced[table] = n
            if referenced:
                print(f'refusing: rows point at {open_act["program_version_id"]}: {referenced}')
                return 1
            counts = {}
            for table in REFERENCING:
                cur.execute(f'SELECT COUNT(*) AS n FROM {table} '
                            f'WHERE user_id = %s AND session_uid LIKE %s', (args.user, args.version + ':%'))
                counts[table] = cur.fetchone()['n']

            stored = get_user_program(args.user) or {}
            envelope = dict(version['program_data'])
            for key in ('revision', 'programVersionId', 'historyRecorded'):
                envelope.pop(key, None)
            print(f'in force now: {open_act["program_version_id"]} from {open_act["effective_from"]} '
                  f'(stored start {ph.start_date_of(stored)}, '
                  f'{len(ph.unwrap(stored).get("weeks") or [])} weeks)')
            print(f'put back:     {args.version} from {own["effective_from"]} '
                  f'(start {version["start_date"]}, {version["week_count"]} weeks)')
            print(f'its sessions carry: {counts}')
            print(f'timeline: activation {open_act["id"]} closes empty at {open_act["effective_from"]}; '
                  f'activation {own["id"]} reopens from {own["effective_from"]}')

            if not args.apply:
                conn.rollback()
                print('\ndry run — pass --apply to save')
                return 0

            cur.execute('UPDATE program_activations SET effective_to = effective_from WHERE id = %s',
                        (open_act['id'],))
            cur.execute('UPDATE program_activations SET effective_to = NULL WHERE id = %s',
                        (own['id'],))
        conn.commit()
    finally:
        conn.close()

    save_user_program(args.user, envelope)
    revision = get_program_revision(args.user)
    out = ph.record_version(args.user, envelope, source='repair', source_revision=revision)
    print(f"\nsaved (revision {revision}); history: {out['reason']} ({out['versionId']})")
    return 0 if out['reason'] == 'already_active' and out['versionId'] == args.version else 2


if __name__ == '__main__':
    sys.exit(main())
