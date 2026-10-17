#!/usr/bin/env python
"""Give every result written before migrations/011 the athlete's day.

`performance_logs.logged_on` is the day a result counts for, where the athlete
was. Rows from before 011 have only `logged_at` (a UTC timestamp), so readers
fall back to its day in the profile's timezone (`src/standards.day_of`). This
writes that day once, computed in Python with each athlete's IANA zone — never
`logged_at::date`, which is the server's UTC day and a day late every evening
west of Greenwich. An athlete without a timezone keeps the UTC day.

Idempotent: only rows whose logged_on is NULL are touched.

    python scripts/backfill_performance_logged_on.py --dry-run
    python scripts/backfill_performance_logged_on.py

Run AFTER migrations/011_standard_results.sql (and scripts/backup_prod.sh).
"""
from __future__ import annotations

import argparse
import os
import sys
from datetime import timezone
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

from src.db import new_conn                    # noqa: E402  (needs DATABASE_URL first)
from src.fit_import import local_date          # noqa: E402


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    conn = new_conn(autocommit=False)
    try:
        with conn.cursor() as cur:
            # user_id is UUID here and TEXT in profiles: compare as text, in Python.
            cur.execute("SELECT user_id::text, profile_data->>'timezone' FROM profiles")
            zones = {u: tz for u, tz in cur.fetchall() if tz}
            cur.execute('SELECT id, user_id::text, logged_at FROM performance_logs WHERE logged_on IS NULL')
            rows = cur.fetchall()
            moved = 0
            for entry_id, user_id, logged_at in rows:
                day = local_date(logged_at, tz=zones.get(user_id))
                moved += int(day != logged_at.astimezone(timezone.utc).strftime('%Y-%m-%d'))
                if not args.dry_run:
                    cur.execute('UPDATE performance_logs SET logged_on = %s WHERE id = %s', (day, entry_id))
        if args.dry_run:
            conn.rollback()
        else:
            conn.commit()
    finally:
        conn.close()
    verb = 'would set' if args.dry_run else 'set'
    print(f'{verb} logged_on on {len(rows)} results ({moved} on a different day than their UTC timestamp)')


if __name__ == '__main__':
    main()
