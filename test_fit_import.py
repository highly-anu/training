#!/usr/bin/env python
"""Guard the FIT import path and the shared workout-id formula.

The parser used to live inside the POST /api/workouts/parse request handler; it
now lives in src/fit_import.py so the Garmin webhook can reuse it. These tests
pin the behaviour that extraction had to preserve.

Run: .venv/bin/python test_fit_import.py
"""
from __future__ import annotations

import hashlib
import io
import os
import sys
from pathlib import Path

# Empty (not absent) so load_dotenv() won't repopulate them from .env:
# auth bypasses to 'local-dev-user' and the DB stays out of the way.
os.environ.setdefault('SUPABASE_URL', '')
os.environ.setdefault('DATABASE_URL', '')
os.environ['SUPABASE_URL'] = ''
os.environ['DATABASE_URL'] = ''

sys.path.insert(0, str(Path(__file__).parent))

from src import fit_import
from src.workout_ids import deterministic_id

FIT_DIR = Path(__file__).parent / 'data'

_failures: list[str] = []


def check(label: str, condition: bool, detail: str = '') -> None:
    if condition:
        print(f'  ok   {label}')
    else:
        print(f'  FAIL {label}' + (f' — {detail}' if detail else ''))
        _failures.append(label)


def test_id_formula() -> None:
    """The formula is referenced by stored rows — it must never move."""
    print('\nDeterministic workout id')
    raw = 'fit_file|2026-03-28T08:00:00+00:00|Running|45'
    expected = 'fit_file-' + hashlib.sha256(raw.encode()).hexdigest()[:24]
    got = deterministic_id('fit_file', '2026-03-28T08:00:00+00:00', 'Running', 45)
    check('formula is source|start|type|duration -> sha256[:24]', got == expected, got)
    check('id is prefixed with its source',
          deterministic_id('garmin', 'x', 'y', 1).startswith('garmin-'))
    check('source changes the id (dedup is a separate layer)',
          deterministic_id('garmin', 'x', 'y', 1) != deterministic_id('fit_file', 'x', 'y', 1))


def test_elevation() -> None:
    print('\ncalc_elevation')
    pts = [{'altitude': 100}, {'altitude': 110}, {'altitude': 105}, {'altitude': 130}]
    check('accumulates gain and loss', fit_import.calc_elevation(pts) == (35.0, 5.0),
          str(fit_import.calc_elevation(pts)))
    check('ignores missing altitudes',
          fit_import.calc_elevation([{'altitude': None}, {'altitude': 100}]) == (0.0, 0.0))
    check('noise floor suppresses jitter',
          fit_import.calc_elevation([{'altitude': 100}, {'altitude': 100.5}]) == (0.0, 0.0))


def test_hr_cleaning() -> None:
    print('\nclean_hr_samples')
    check('empty in, empty out', fit_import.clean_hr_samples([]) == [])
    steady = [{'timestamp': f'2026-03-28T08:00:{i:02d}+00:00', 'bpm': 150} for i in range(10)]
    check('steady signal survives intact', len(fit_import.clean_hr_samples(steady)) == 10)
    # 300 bpm is physiologically impossible and must be dropped.
    noisy = steady + [{'timestamp': '2026-03-28T08:00:10+00:00', 'bpm': 300}]
    check('impossible readings are filtered',
          all(s['bpm'] <= 250 for s in fit_import.clean_hr_samples(noisy)))


def test_parse_fit() -> None:
    print('\nparse_fit against the repo fixtures')
    fits = sorted(FIT_DIR.glob('*.fit'))
    if not fits:
        check('fixture .fit files present in data/', False, 'none found')
        return

    for path in fits:
        with open(path, 'rb') as fh:
            workouts = fit_import.parse_fit(fh)
        label = path.name
        check(f'{label}: parses to at least one session', len(workouts) >= 1)
        if not workouts:
            continue
        w = workouts[0]
        check(f'{label}: tagged source=fit_file by default', w['source'] == 'fit_file')
        check(f'{label}: id matches the shared formula',
              w['id'] == deterministic_id('fit_file', w['startTime'],
                                          w['activityType'], w['durationMinutes']))
        check(f'{label}: has a GPS track', bool(w.get('gpsTrack')))
        check(f'{label}: has HR samples', bool(w['heartRate'].get('samples')))
        check(f'{label}: date agrees with startTime', w['date'] == w['startTime'][:10])
        check(f'{label}: duration is positive', w['durationMinutes'] > 0)

    # The source parameter is what lets the Garmin webhook reuse this parser.
    with open(fits[0], 'rb') as fh:
        as_garmin = fit_import.parse_fit(fh, source='garmin')
    check('source parameter retags the workout', as_garmin[0]['source'] == 'garmin')
    check('source parameter changes the id', as_garmin[0]['id'].startswith('garmin-'))

    # Accepting raw bytes matters: the webhook passes io.BytesIO(response.content).
    with open(fits[0], 'rb') as fh:
        from_bytes = fit_import.parse_fit(io.BytesIO(fh.read()))
    check('parses from an in-memory buffer', from_bytes[0]['id'] == workouts_first_id(fits[0]))


def workouts_first_id(path: Path) -> str:
    with open(path, 'rb') as fh:
        return fit_import.parse_fit(fh)[0]['id']


def test_endpoint_still_works() -> None:
    """The three parse endpoints kept their shapes after the extraction."""
    print('\nPOST /api/workouts/parse')
    import api
    client = api.app.test_client()

    fits = sorted(FIT_DIR.glob('*.fit'))
    if fits:
        with open(fits[0], 'rb') as fh:
            r = client.post('/api/workouts/parse',
                            data={'workout_file': (fh, fits[0].name)},
                            content_type='multipart/form-data')
        check('.fit upload returns 200', r.status_code == 200, str(r.status_code))
        check('.fit upload returns a workout list', isinstance(r.get_json(), list))

    r = client.post('/api/workouts/parse',
                    data={'workout_file': (io.BytesIO(b'[]'), 'a.json')},
                    content_type='multipart/form-data')
    check('.json branch still handled', r.status_code == 200, str(r.status_code))

    r = client.post('/api/workouts/parse',
                    data={'workout_file': (io.BytesIO(b'x'), 'a.txt')},
                    content_type='multipart/form-data')
    check('unsupported extension still 415', r.status_code == 415, str(r.status_code))

    check('api._calc_elevation is the shared implementation',
          api._calc_elevation is fit_import.calc_elevation)
    check('api._clean_hr_samples is the shared implementation',
          api._clean_hr_samples is fit_import.clean_hr_samples)


if __name__ == '__main__':
    test_id_formula()
    test_elevation()
    test_hr_cleaning()
    test_parse_fit()
    test_endpoint_still_works()

    if _failures:
        print(f'\n{len(_failures)} FIT import test(s) failed.')
        sys.exit(1)
    print('\nAll FIT import tests passed.')
