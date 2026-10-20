#!/usr/bin/env python
"""The Dev Lab's recorded traces keep the shape /programs/generate?trace=1 has.

frontend/src/mocks/fixtures/traced-programs.json holds real generate?trace=1
answers, and frontend/src/components/devlab/DevLabPanels.test.tsx renders every
Dev Lab panel against them. The Schedule step once crashed the page for every
program: since tracks (2026-10-13) each week's phase names its framework, a
path whose trace records no `alternatives_checked`, while the panel and a
hand-written type said the field was always there. This test sends the same
requests again and fails when the trace's keys differ from the recording's, so
a change to the trace is re-recorded and the panels meet it in their own test.

Only the keys are compared, never the values: a package edit that changes
what gets picked is not a change of shape.

Run: SUPABASE_URL='' .venv/bin/python test_devlab_trace.py
     SUPABASE_URL='' .venv/bin/python test_devlab_trace.py --record   # after a trace change
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

os.environ.setdefault('SUPABASE_URL', '')

FIXTURE = Path(__file__).parent / 'frontend/src/mocks/fixtures/traced-programs.json'

_ATHLETE = {
    'days_per_week': 3, 'session_time_minutes': 60, 'avoid_movements': [],
    'periodization_week': 1, 'fatigue_state': 'normal', 'injury_flags': [],
}

# Each one reaches a different corner of the trace; what it is for is its name.
SCENARIOS: dict[str, dict] = {
    # Slots emptied for equipment. (Starting Strength was this scenario until
    # its training contract began refusing a program with no barbell.)
    'gym_jones_no_equipment': {
        'philosophy_id': 'gym_jones', 'num_weeks': 1,
        'constraints': {**_ATHLETE, 'days_per_week': 5, 'session_time_minutes': 90,
                        'equipment': [], 'training_level': 'intermediate'},
    },
    # Injury-blocked slots, a session swapped to another modality because
    # nothing is written for a novice, a level-locked slot and a test session.
    # Horsemen runs its source's week templates (src/week_template.py): each
    # day a named workout forced from its category's pool. It has no novice path.
    'horsemen_injured': {
        'philosophy_id': 'horsemen_gpp', 'num_weeks': 1,
        'constraints': {**_ATHLETE, 'days_per_week': 5, 'training_level': 'intermediate',
                        'equipment': ['barbell', 'rack', 'plates', 'kettlebell', 'pull_up_bar', 'open_space'],
                        'injury_flags': ['shoulder_impingement', 'lumbar_disc']},
    },
    # A training contract places fixed modules (src/training_contract.py): its
    # trace has no framework selection, allocation or candidates.
    'wildman_general_practice_contract': {
        'philosophy_id': 'wildman_kettlebell', 'track_id': 'general_practice', 'num_weeks': 1,
        'constraints': {**_ATHLETE, 'days_per_week': 4, 'training_level': 'intermediate',
                        'equipment': ['kettlebell', 'open_space']},
    },
}

# Maps keyed by data (day names, modality ids, a progression model's outputs):
# their keys are not the trace's shape.
_DATA_MAPS = {'sessions', 'phase_priorities', 'raw', 'final', 'assignments', 'output'}


def key_paths(node, path: str = '', out: set | None = None) -> set[str]:
    out = set() if out is None else out
    if isinstance(node, dict):
        data_map = path.rsplit('.', 1)[-1] in _DATA_MAPS
        for key, value in node.items():
            child = f"{path}.{'*' if data_map else key}"
            out.add(child)
            key_paths(value, child, out)
    elif isinstance(node, list):
        for item in node:
            key_paths(item, f'{path}[]', out)
    return out


def generate(client, request: dict) -> dict:
    res = client.post('/api/programs/generate?trace=1', json=request)
    assert res.status_code == 200, (res.status_code, res.get_data(as_text=True)[:300])
    body = res.get_json()
    assert body.get('generation_trace', {}).get('weeks'), 'no trace: the request is infeasible'
    return body


def main() -> int:
    import api
    client = api.app.test_client()

    if '--record' in sys.argv:
        recording = {
            '_about': 'Real /programs/generate?trace=1 answers for the Dev Lab panel test. '
                      'Re-record with test_devlab_trace.py --record; never edit by hand.',
            'scenarios': {name: {'request': req, 'response': generate(client, req)}
                          for name, req in SCENARIOS.items()},
        }
        FIXTURE.write_text(json.dumps(recording, indent=1, ensure_ascii=False) + '\n')
        print(f'recorded {len(SCENARIOS)} scenarios → {FIXTURE.relative_to(Path(__file__).parent)}')
        return 0

    recorded = json.loads(FIXTURE.read_text())['scenarios']
    failures = 0
    if set(recorded) != set(SCENARIOS):
        print(f'  FAIL scenarios differ: recorded {sorted(recorded)}, defined {sorted(SCENARIOS)}')
        failures += 1
    for name, req in SCENARIOS.items():
        if name not in recorded:
            continue
        if recorded[name]['request'] != req:
            print(f'  FAIL {name}: the request changed since it was recorded')
            failures += 1
            continue
        then = key_paths(recorded[name]['response']['generation_trace'])
        now = key_paths(generate(client, req)['generation_trace'])
        if then == now:
            print(f'  ok   {name}: {len(now)} trace keys as recorded')
            continue
        failures += 1
        print(f'  FAIL {name}: the trace changed shape')
        for p in sorted(now - then):
            print(f'         + {p}')
        for p in sorted(then - now):
            print(f'         - {p}')
    if failures:
        print('Re-record with --record, then run the panels\' test: '
              'cd frontend && npx vitest run src/components/devlab')
        return 1
    print('all passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
