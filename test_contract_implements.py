#!/usr/bin/env python
"""A training contract's implement is data: any equipment, not the kettlebell.

Stages a copy of Wildman beside the shipped packages (`TRAINING_PACKAGES_DIR`,
the drop-in test's renaming, so no id collides) whose implement is a pair of
dumbbells instead of bells, and runs its double track: the builders are told
to confirm `dumbbell_count`, the program is refused without it and generated
with it, the athlete's `dumbbell_weights_kg` bounds the weight, and every note
and refusal says "dumbbell" — while Wildman's own track still asks for, and
says, bells (roadmap 9.5; src/implements.py).

    SUPABASE_URL='' .venv/bin/python test_contract_implements.py
"""
from __future__ import annotations

import atexit
import os
import re
import shutil
import sys
import tempfile

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)
os.environ.setdefault('SUPABASE_URL', '')
os.environ.setdefault('DATABASE_URL', '')

COPY = 'zz_dumbbell_practice'
TRACK = 'double_bell_practice'


def _stage() -> None:
    from test_package_dropin import make_packages
    folder = tempfile.mkdtemp(prefix='packages-')
    atexit.register(shutil.rmtree, folder, True)
    make_packages(folder, {COPY: 'data/packages/wildman_kettlebell'})
    path = os.path.join(folder, COPY, 'training_contract.yaml')
    text = open(path, encoding='utf-8').read()
    text, n = re.subn(r'^implement: \{equipment: kettlebell\}$', 'implement: {equipment: dumbbell}', text, flags=re.M)
    assert n == 1, 'the copy names its implement once'
    open(path, 'w', encoding='utf-8').write(text)
    os.environ['TRAINING_PACKAGES_DIR'] = folder


_stage()

from unittest.mock import patch  # noqa: E402

FAILURES: list[str] = []


def check(label: str, condition: bool, detail='') -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        FAILURES.append(label)


def _generate(client, pkg: str, **extra):
    athlete = {'equipment': ['kettlebell', 'dumbbell', 'open_space'], 'injury_flags': [], 'training_level': 'intermediate',
               'days_per_week': 4, 'session_time_minutes': 60,
               'mastered_exercises': _mastery(pkg), **extra}
    with patch('src.db.get_user_program', return_value=None), patch('src.db.save_user_program'):
        r = client.post('/api/programs/generate', json={'philosophy_id': pkg, 'track_id': TRACK, 'num_weeks': 2,
                                                        'persist': False, 'constraints': athlete})
    return r.status_code, r.get_json() or {}


def _mastery(pkg: str) -> list[str]:
    """Every movement the track asks to be confirmed."""
    from src import training_contract
    contract = training_contract.load_contract(pkg, TRACK)
    return sorted({e for m in contract['modules'] for e in m.get('requires_mastery') or []})


def _notes(body: dict) -> list[str]:
    # The API surfaces a load's note on the assignment (api._clean_exercise_assignment).
    return [ea.get('load_note') or '' for w in body.get('weeks') or [] for ss in w['schedule'].values()
            for s in ss for ea in s.get('exercises') or [] if ea.get('load_note')]


def _refusal(body: dict) -> str:
    return ' '.join([str(body.get('detail') or '')] + [e.get('message', '') for e in
                                                        (body.get('validation') or {}).get('errors') or []])


def main() -> int:
    from src import training_contract
    print('the contract')
    contract = training_contract.load_contract(COPY, TRACK)
    check('the track takes the document\'s implement and its own count',
          contract.get('implement') == {'equipment': 'dumbbell', 'count': 2}, contract.get('implement'))
    check("Wildman's is the kettlebell, two for its double track",
          training_contract.load_contract('wildman_kettlebell', TRACK).get('implement')
          == {'equipment': 'kettlebell', 'count': 2})

    import api
    client = api.app.test_client()
    print('the builders are told what to confirm')
    tracks = {(p['id'], t['id']): t for p in client.get('/api/philosophies').get_json() for t in p.get('tracks') or []}
    mine = tracks[(COPY, TRACK)]['entry_requirements']
    check('a pair of dumbbells, by dumbbell_count', mine.get('implements') == [
        {'equipment': 'dumbbell', 'count': 2, 'countKey': 'dumbbell_count', 'number': 'two', 'plural': 'dumbbells'}],
        mine.get('implements'))
    check('and no kettlebell for builds that read only that', mine.get('kettlebell_count') == 1)
    wild = tracks[('wildman_kettlebell', TRACK)]['entry_requirements']
    check("Wildman's still asks for two kettlebells", wild.get('kettlebell_count') == 2
          and [i['countKey'] for i in wild.get('implements') or []] == ['kettlebell_count'])

    print('generation')
    status, body = _generate(client, COPY, kettlebell_count=2)
    check('refused without the pair of dumbbells, saying so',
          not body.get('weeks') and 'two matching dumbbells; confirm dumbbell_count of at least 2' in _refusal(body),
          (status, _refusal(body)[:300]))
    status, body = _generate(client, COPY, dumbbell_count=2)
    notes = _notes(body)
    check('generated with them', status == 200 and bool(body.get('weeks')), (status, _refusal(body)[:300]))
    check('its notes say dumbbell, never bell', any('dumbbell' in n for n in notes)
          and not any(re.search(r'\bbells?\b', n) for n in notes), [n for n in notes if 'bell' in n][:3])
    status, body = _generate(client, COPY, dumbbell_count=2, dumbbell_weights_kg=[20],
                             module_progression_state={'double_strength': {'completed': 0, 'weight_kg': 24}})
    check('a weight the athlete does not own is refused, as a dumbbell',
          not body.get('weeks') and 'the selected dumbbell is not in the available inventory' in _refusal(body),
          (status, _refusal(body)[:300]))
    status, body = _generate(client, COPY, dumbbell_count=2, dumbbell_weights_kg=[20],
                             module_progression_state={'double_strength': {'completed': 0, 'weight_kg': 20}})
    notes = _notes(body)
    check('one they own is used, per dumbbell', status == 200 and any(
        'Use two matching dumbbells; selected weight is per dumbbell.' in n for n in notes), notes[:3])

    print("Wildman's own track")
    status, body = _generate(client, 'wildman_kettlebell', kettlebell_count=2, kettlebell_weights_kg=[16],
                             module_progression_state={'double_strength': {'completed': 0, 'weight_kg': 16}})
    check('still says bells', any('Use two matching bells; selected weight is per bell.' in n for n in _notes(body)),
          _notes(body)[:3])

    print('Explore')
    from src import explore_philosophy
    tracks = {t['id']: t for t in (explore_philosophy.describe(COPY) or {}).get('tracks') or []}
    check('a track card says what it needs in words', tracks.get(TRACK, {}).get('implement') == 'a pair of dumbbells',
          tracks.get(TRACK, {}).get('implement'))
    wild = {t['id']: t for t in (explore_philosophy.describe('wildman_kettlebell') or {}).get('tracks') or []}
    check("and Wildman's a pair of bells", wild.get(TRACK, {}).get('implement') == 'a pair of bells')
    if FAILURES:
        print(f'{len(FAILURES)} failed')
        return 1
    print('all passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
