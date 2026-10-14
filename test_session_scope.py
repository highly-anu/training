#!/usr/bin/env python
"""Whether a match or a session log belongs to the active program (no DB).

The fixtures are the production rows of 2026-10-14: a Wildman program started
2026-10-12, in its first week, showed week 6 Monday and Wednesday completed
and linked, and week 5 Friday and Sunday linked — all from March and April
rows with no session_uid, which every reader trusted on their key alone.

Run: .venv/bin/python test_session_scope.py
"""
from __future__ import annotations

import sys
from datetime import date, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from src import session_scope as sc

_failures: list[str] = []


def check(label: str, condition: bool, detail: str = '') -> None:
    if condition:
        print(f'  ok   {label}')
    else:
        print(f'  FAIL {label}' + (f' — {detail}' if detail else ''))
        _failures.append(label)


VID = 'b2840d32b7b5040d376c067f331a97c2'
OLD = '33bd69d059fa77b38d2eb5139ba2b1d0'
START = date(2026, 10, 12)                      # a Monday
DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
PLANNED = {f'{w + 1}-{d}-0': START + timedelta(days=7 * w + i)
           for w in range(16) for i, d in enumerate(DAYS)}
PLANNED['1-Tuesday-1'] = START + timedelta(days=1)   # a second session that day


def match(key, uid=None):
    return {'sessionKey': key, 'sessionUid': uid, 'matchConfidence': 'auto'}


def test_the_production_rows() -> None:
    print('\nthe April rows on an October program')
    check('week 6 Monday: a 2026-04-08 workout does not link it',
          not sc.match_in_active(match('6-Wednesday-0'), '2026-04-08', VID, PLANNED))
    check('week 5 Friday: a 2026-04-03 workout does not link it',
          not sc.match_in_active(match('5-Friday-0'), date(2026, 4, 3), VID, PLANNED))
    check('a match whose workout is gone does not link it',
          not sc.match_in_active(match('6-Monday-0'), None, VID, PLANNED))
    check('week 6 Monday: an April completion does not complete it',
          not sc.log_in_active(None, '6-Monday-0', '2026-04-06 20:09:11+00:00', VID, PLANNED))
    check('an unscoped log never completed does not belong',
          not sc.log_in_active(None, '5-Friday-0', None, VID, PLANNED))


def test_this_programs_rows() -> None:
    print('\nthis program\'s own rows')
    check('a scoped match of this version belongs',
          sc.match_in_active(match('1-Tuesday-0', f'{VID}:w0-Tuesday-0'), '2026-10-13', VID, PLANNED))
    check('a scoped match of another version does not',
          not sc.match_in_active(match('1-Tuesday-0', f'{OLD}:w3-Tuesday-0'), '2026-10-13', VID, PLANNED))
    check('an unscoped match on the planned day belongs',
          sc.match_in_active(match('1-Wednesday-0'), '2026-10-14', VID, PLANNED))
    check('...and a day either side (a UTC-dated evening)',
          sc.match_in_active(match('1-Wednesday-0'), '2026-10-15', VID, PLANNED)
          and sc.match_in_active(match('1-Wednesday-0'), '2026-10-13', VID, PLANNED))
    check('...but not two days off',
          not sc.match_in_active(match('1-Wednesday-0'), '2026-10-16', VID, PLANNED))
    check('a scoped log completed on the day belongs',
          sc.log_in_active(f'{VID}:w0-Tuesday-0', '1-Tuesday-0', '2026-10-13T18:00:00+00:00', VID, PLANNED))
    check('a scoped log with sets but no completion belongs',
          sc.log_in_active(f'{VID}:w0-Tuesday-0', '1-Tuesday-0', None, VID, PLANNED))
    check('a log completed late belongs (logged the next week)',
          sc.log_in_active(f'{VID}:w0-Tuesday-0', '1-Tuesday-0', '2026-10-21', VID, PLANNED))
    check('Sunday done on Wednesday of the same week belongs',
          sc.log_in_active(f'{VID}:w0-Sunday-0', '1-Sunday-0', '2026-10-14', VID, PLANNED))


def test_stale_client() -> None:
    print('\na stale client writing an old program\'s week 6')
    # program_history.active_session_uid stamps by key alone, so this lands
    # on the active version's uid — only the date gives it away.
    check('a log completed today for week 6 is not this program\'s week 6',
          not sc.log_in_active(f'{VID}:w5-Monday-0', '6-Monday-0', '2026-10-14T07:00:00+00:00',
                               VID, PLANNED))
    check('a scoped log of another version never belongs',
          not sc.log_in_active(f'{OLD}:w5-Monday-0', '6-Monday-0', '2026-10-14', VID, PLANNED))


def test_a_spliced_program() -> None:
    print('\na week number that appears twice')
    # active_plan_dates leaves a duplicated key out and dates each uid instead.
    planned = {k: v for k, v in PLANNED.items() if k != '3-Monday-0'}
    planned[f'{VID}:w2-Monday-0'] = date(2026, 10, 26)
    check('a scoped log on a duplicated key is dated by its uid',
          sc.log_in_active(f'{VID}:w2-Monday-0', '3-Monday-0', '2026-10-26', VID, planned))
    check('an unscoped one cannot be placed',
          not sc.log_in_active(None, '3-Monday-0', '2026-10-26', VID, planned))


def test_keys_and_fallbacks() -> None:
    print('\nkey shapes and no history')
    check('a day-level key resolves when the day has one session',
          sc.planned_date(PLANNED, '1-Wednesday') == date(2026, 10, 14))
    check('...and when it has two, which share the date',
          sc.planned_date(PLANNED, '1-Tuesday') == date(2026, 10, 13))
    check('an unknown key has no date', sc.planned_date(PLANNED, '40-Monday-0') is None)
    check('without history every row is kept, as before',
          sc.match_in_active(match('6-Monday-0'), '2026-04-06', None, {})
          and sc.log_in_active(None, '6-Monday-0', None, None, {}))


if __name__ == '__main__':
    test_the_production_rows()
    test_this_programs_rows()
    test_stale_client()
    test_a_spliced_program()
    test_keys_and_fallbacks()
    if _failures:
        print(f'\n{len(_failures)} failed')
        sys.exit(1)
    print('\nall passed')
