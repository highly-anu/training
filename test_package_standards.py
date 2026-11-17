#!/usr/bin/env python
"""A package's own standards: data/packages/<id>/standards.yaml.

Beside the commons' (data/benchmarks/), found by glob, with their own
category if they need one (roadmap 9.2). Staged beside the shipped packages
in a packages folder of its own (`TRAINING_PACKAGES_DIR`, the drop-in test's
copies, ids renamed): a package that brings two standards, one in a group it
adds. Checks that they load after the commons' (whose order does not move),
reach the API with their group's name and place, validate — and refuse an id
the commons or another package already has, an unknown group, and a
reference from a package that does not borrow from the owner.

    SUPABASE_URL='' .venv/bin/python test_package_standards.py
"""
from __future__ import annotations

import atexit
import os
import shutil
import sys
import tempfile

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)
os.environ.setdefault('SUPABASE_URL', '')
os.environ.setdefault('DATABASE_URL', '')

OWNER = 'dropin_scheduler'      # brings the standards
STRANGER = 'dropin_contract'    # neither owns nor borrows them
STANDARDS = """\
categories:
  - id: dropin_group
    name: Drop-in group
standards:
  - id: dropin_hang_seconds
    name: Dead hang (seconds)
    category: dropin_group
    domain: durability
    metric_type: time_seconds
    levels:
      entry: {male: 30, female: 20}
      intermediate: {male: 60, female: 45}
      advanced: {male: 90, female: 70}
      elite: {male: 120, female: 100}
  - id: dropin_carry_metres
    name: Farmer carry (metres)
    domain: durability
    category: strength
    metric_type: distance_m
    levels:
      entry: {male: 50, female: 40}
      intermediate: {male: 100, female: 80}
      advanced: {male: 150, female: 120}
      elite: {male: 200, female: 160}
"""
TEST_ARCHETYPE = """\
id: {id}
name: Hang test
modality: durability
category: conditioning
test: true
duration_estimate_minutes: 10
required_equipment: [pull_up_bar]
training_levels: [novice, intermediate, advanced, elite]
applicable_phases: [base, build, peak, taper, maintenance, deload, transition, specific, rehab]
slots:
  - role: hang
    slot_type: static_hold
    hold_seconds: 120
    standard: dropin_hang_seconds
    exercise_filter:
      exercise_ids: [dead_hang]
"""


def _stage() -> str:
    from test_package_dropin import make_packages
    folder = tempfile.mkdtemp(prefix='packages-')
    atexit.register(shutil.rmtree, folder, True)
    make_packages(folder)
    with open(os.path.join(folder, OWNER, 'standards.yaml'), 'w', encoding='utf-8') as fh:
        fh.write(STANDARDS)
    os.environ['TRAINING_PACKAGES_DIR'] = folder
    return folder


FOLDER = _stage()

from src import portability  # noqa: E402
from src.analytics import benchmarks_data as bd  # noqa: E402
from tools import validate_entities as ve  # noqa: E402

FAILURES: list[str] = []


def check(label: str, condition: bool, detail='') -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        FAILURES.append(label)


def _commons_ids() -> list[str]:
    return [b['id'] for b in bd.load_benchmarks() if not b.get('package')]


def test_loaded():
    print('loaded beside the commons')
    by_id = bd.by_id()
    hang, carry = by_id.get('dropin_hang_seconds'), by_id.get('dropin_carry_metres')
    check('both load, owned by the package', hang and carry and hang['package'] == carry['package'] == OWNER)
    check("a package standard belongs to its philosophy", hang and hang['sources'] == [OWNER], hang)
    cats = bd.categories()
    check('the group it adds comes after the commons ones', cats[-1] == ('dropin_group', 'Drop-in group'), cats)
    order = [b['id'] for b in bd.load_benchmarks()]
    strength = [b['id'] for b in bd.load_benchmarks() if b['category'] == 'strength']
    check('one in a commons group is listed last in it', strength[-1] == 'dropin_carry_metres', strength[-3:])
    check('one in its own group is listed last of all', order[-1] == 'dropin_hang_seconds', order[-3:])
    check('the commons keep their order', _commons_ids() == [i for i in order if not i.startswith('dropin_')])
    check('a result may be stored under it', 'dropin_hang_seconds' in bd.known_ids())
    client = bd.to_client(hang)
    check('the client is told its group and place',
          client['categoryName'] == 'Drop-in group' and client['categoryOrder'] == len(cats) - 1, client)
    check('its level reads like any other', bd.level_of(hang, 95)['level'] == 'advanced',
          bd.level_of(hang, 95))
    from tools import check_code_neutral as neutral
    owned = neutral.owned_ids().get(OWNER, {})
    check('code naming one would name the package (X1)',
          owned.get('dropin_hang_seconds') == 'standard' and owned.get('dropin_group') == 'standard category',
          {k: v for k, v in owned.items() if k.startswith('dropin_') and 'standard' in v})


def test_route():
    print('the API')
    import api
    rows = api.app.test_client().get('/api/standards').get_json()
    mine = [r for r in rows if r['id'].startswith('dropin_')]
    check('GET /api/standards serves them', {r['id'] for r in mine} == {'dropin_hang_seconds', 'dropin_carry_metres'},
          [r['id'] for r in mine])
    check('with the group name', any(r.get('categoryName') == 'Drop-in group' for r in mine))


def _write(rel: str, text: str) -> str:
    path = os.path.join(FOLDER, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as fh:
        fh.write(text)
    atexit.register(lambda: os.path.exists(path) and os.remove(path))
    return path


def test_validation():
    print('validation')
    own = os.path.join(FOLDER, OWNER, 'standards.yaml')
    check('the file validates', ve.validate_file(own, verbose=False) == [], ve.validate_file(own, verbose=False))
    bad = _write(f'{STRANGER}/standards.yaml', STANDARDS.replace('category: dropin_group', 'category: nowhere')
                 .replace('dropin_carry_metres', 'back_squat_bw_ratio').replace('dropin_hang_seconds', 'zz_other'))
    errors = ve.validate_file(bad, verbose=False)
    check('an unknown group is refused', any("category 'nowhere'" in e for e in errors), errors)
    check("a commons id is refused", any('back_squat_bw_ratio' in e and 'commons' in e for e in errors), errors)
    os.remove(bad)

    twin = _write(f'{STRANGER}/standards.yaml', STANDARDS)
    collided = {(c['kind'], c['id']) for c in portability.id_collisions()}
    check("another package's id collides", ('standard', 'dropin_hang_seconds') in collided, collided)
    os.remove(twin)
    check('and without the twin, none', not portability.id_collisions(), portability.id_collisions())

    foreign = _write(f'{STRANGER}/archetypes/zz_hang_test.yaml', TEST_ARCHETYPE.format(id='zz_hang_test_a'))
    errors = ve.validate_file(foreign, verbose=False)
    check("a package that does not borrow it may not measure it",
          any(f"is {OWNER}'s" in e and STRANGER in e for e in errors), errors)
    mine = _write(f'{OWNER}/archetypes/zz_hang_test.yaml', TEST_ARCHETYPE.format(id='zz_hang_test_b'))
    errors = ve.validate_file(mine, verbose=False)
    check('its own package may', not any('borrow' in e for e in errors), errors)


def main() -> int:
    test_loaded()
    test_route()
    test_validation()
    if FAILURES:
        print(f'{len(FAILURES)} failed')
        return 1
    print('all passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
