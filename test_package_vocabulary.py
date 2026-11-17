#!/usr/bin/env python
"""A package's own vocabulary (docs/roadmap.md 20.6): `vocabulary.yaml` adds
modalities and movement patterns for the package that declares them.

The package is the modality scheduler's fixture with one modality of its own
in place of `power` — its framework schedules it, its archetype trains it —
and one exercise on a movement pattern of its own, read as the caller's
overlay on the repository's packages, unchanged:

  - the validator holds the file to the commons (families, tints, regions,
    injury flags, progression models) and refuses an id the commons define;
  - the gate passes the package, and refuses the same package without its
    vocabulary — the modality is nobody's;
  - inside the view the modality schedules, rolls up into its family and is
    served with its display; the pattern loads its regions and the injury
    flags it names rule it out; outside the view none of it exists.

Run: SUPABASE_URL='' .venv/bin/python test_package_vocabulary.py
"""
from __future__ import annotations

import atexit
import os
import re
import shutil
import sys
import tempfile

os.environ.setdefault('SUPABASE_URL', '')
os.environ.setdefault('DATABASE_URL', '')
os.environ.pop('TRAINING_PACKAGES_DIR', None)

ROOT = os.path.dirname(os.path.abspath(__file__))
FIXTURE = 'block_fixture'
MODALITY, PATTERN, FLAG, IMPLEMENT = 'sled_work', 'sled_push', 'knee_meniscus_post_op', 'zz_prowler'

import yaml  # noqa: E402

from src import loader, package_gate, portability, recovery_regions  # noqa: E402
from src.analytics import families  # noqa: E402
from tools import validate_entities  # noqa: E402

FAILURES: list[str] = []

VOCABULARY = f'''modalities:
  - id: {MODALITY}
    name: Sled work
    description: Heavy sled pushes and drags.
    recovery_cost: high
    recovery_hours_min: 48
    session_position: first
    priority_tier: 2
    typical_duration_minutes: 45
    progression_model: linear_load
    family: strength
    compatible_in_session_with: [mobility]
    display:
      label: Sled
      short: Sled
      order: 20
      color: '#b91c1c'
      tint: red
      text_shade: 700
      icon: {{web: Weight, ios: figure.strengthtraining.traditional, watch: figure.strengthtraining.traditional}}
movement_patterns:
  - id: {PATTERN}
    name: Sled push
    regions: {{lower: 1, trunk: 0.5}}
    excluded_by: [{FLAG}]
equipment:
  - {{id: {IMPLEMENT}, label: Prowler}}
'''

EXERCISE = f'''- id: zz_sled_push
  name: Sled Push
  category: accessory
  modality:
  - {MODALITY}
  equipment:
  - {IMPLEMENT}
  effort: high
  movement_patterns:
  - {PATTERN}
'''


def check(label: str, condition: bool, detail='') -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        FAILURES.append(label)


def scratch() -> str:
    folder = tempfile.mkdtemp(prefix='vocabulary-')
    atexit.register(shutil.rmtree, folder, True)
    return folder


def edit(path: str, fn) -> None:
    with open(path, encoding='utf-8') as fh:
        text = fh.read()
    with open(path, 'w', encoding='utf-8') as fh:
        fh.write(fn(text))


def stage(vocabulary: str | None = VOCABULARY) -> tuple[str, str]:
    """An overlay with the fixture, its `power` work given to the package's
    own modality. → (overlay, package folder)."""
    overlay = scratch()
    pkg = os.path.join(overlay, FIXTURE)
    shutil.copytree(os.path.join(ROOT, 'test_packages', FIXTURE), pkg)
    edit(os.path.join(pkg, 'archetypes', 'strength', 'barbell_power_complex.yaml'),
         lambda t: t.replace('modality: power', f'modality: {MODALITY}'))
    edit(os.path.join(pkg, 'frameworks', 'block_periodization.yaml'),
         lambda t: t.replace('  - power\n', f'  - {MODALITY}\n').replace('  power: 1\n', f'  {MODALITY}: 1\n')
                    .replace('core: [mixed_modal_conditioning, power]', f'core: [mixed_modal_conditioning, {MODALITY}]'))
    edit(os.path.join(pkg, 'philosophy.yaml'), lambda t: re.sub(r'^  - power$', f'  - {MODALITY}', t, flags=re.M))
    # Without a vocabulary the exercise needs a commons implement: the schema
    # refuses any other before the id check is reached (test_gate).
    exercise = EXERCISE if vocabulary is not None else EXERCISE.replace(IMPLEMENT, 'sled')
    edit(os.path.join(pkg, 'exercises.yaml'), lambda t: t.replace('exercises:\n', 'exercises:\n' + exercise, 1))
    if vocabulary is not None:
        with open(os.path.join(pkg, 'vocabulary.yaml'), 'w', encoding='utf-8') as fh:
            fh.write(vocabulary)
    return overlay, pkg


def errors_of(vocabulary: str) -> list[str]:
    _, pkg = stage(vocabulary)
    return validate_entities.validate_file(os.path.join(pkg, 'vocabulary.yaml'), verbose=False)


def test_validator():
    print('the validator')
    overlay, pkg = stage()
    found = {os.path.relpath(p, pkg): e for p, e in validate_entities.validate_path(pkg, verbose=False).items() if e}
    check('the package validates, its vocabulary included', not found, found)
    doc = yaml.safe_load(VOCABULARY)

    def with_modality(**changes):
        d = yaml.safe_load(VOCABULARY)
        d['modalities'][0].update(changes)
        return yaml.safe_dump(d)

    def with_pattern(**changes):
        d = yaml.safe_load(VOCABULARY)
        d['movement_patterns'][0].update(changes)
        return yaml.safe_dump(d)

    def has(errors, text):
        return any(text in e for e in errors)

    check('a modality id the commons define is refused', has(errors_of(with_modality(id='power')), 'already define'))
    check('a family that is not one', has(errors_of(with_modality(family='lifting')), "family 'lifting'"))
    check('a progression model the engine does not have',
          has(errors_of(with_modality(progression_model='vibes')), "'vibes' is not one of"))
    check('a tint the clients do not carry', has(errors_of(with_modality(display={**doc['modalities'][0]['display'],
                                                                                 'tint': 'fuchsia'})), "tint 'fuchsia'"))
    no_display = yaml.safe_load(VOCABULARY)
    del no_display['modalities'][0]['display']
    check('a modality without its display', bool(errors_of(yaml.safe_dump(no_display))))
    check('a session partner that is nobody\'s', has(errors_of(with_modality(compatible_in_session_with=['yoga'])),
                                                     "names 'yoga'"))
    check('a pattern id the commons define', has(errors_of(with_pattern(id='squat')), 'already define'))
    check('a region that is not one', has(errors_of(with_pattern(regions={'arms': 1})), "region 'arms'"))
    check('an injury flag that is not one', has(errors_of(with_pattern(excluded_by=['bad_mood'])), "'bad_mood'"))
    taken = yaml.safe_load(VOCABULARY)
    taken['equipment'][0]['id'] = 'barbell'
    alias = yaml.safe_load(VOCABULARY)
    alias['equipment'][0]['id'] = 'assault_bike'
    check('an implement id the commons list, or an alias of one', has(errors_of(yaml.safe_dump(taken)), 'already list')
          and has(errors_of(yaml.safe_dump(alias)), 'already list'))
    silent = yaml.safe_load(VOCABULARY)
    del silent['movement_patterns'][0]['excluded_by']
    check('a pattern must say which injuries rule it out (none is an answer)', bool(errors_of(yaml.safe_dump(silent)))
          and not errors_of(with_pattern(excluded_by=[])))


def test_gate():
    print('the gate')
    overlay, pkg = stage()
    with loader.overlay(overlay):
        result = package_gate.check_package(pkg)
        check('the package passes every stage and generates', result['ok'], {'problems': result['problems'][:3],
                                                                             'skipped': result['skipped']})
        loose = package_gate.check_package(pkg, smoke=False, owner_prefix='u1a2b3c4d_')
        named = {p['message'].split("'")[1] for p in loose['problems'] if p['code'] == 'not_prefixed'}
        check("as an athlete's own, its modality, pattern and implement need the owner's prefix",
              {MODALITY, PATTERN, IMPLEMENT} <= named, sorted(named))
    bare, bare_pkg = stage(vocabulary=None)
    with loader.overlay(bare):
        result = package_gate.check_package(bare_pkg, smoke=False)
        unknown = [p['message'] for p in result['problems'] if p['code'] == 'unknown_id']
        check('without its vocabulary the modality and the pattern are nobody\'s',
              any(MODALITY in m for m in unknown) and any(PATTERN in m for m in unknown), result['problems'][:4])
        check('and the message says where to declare them', any('vocabulary.yaml' in m for m in unknown), unknown[:1])
    undeclared, undeclared_pkg = stage(VOCABULARY.replace(f'id: {IMPLEMENT}', 'id: zz_other'))
    with loader.overlay(undeclared):
        result = package_gate.check_package(undeclared_pkg, smoke=False)
        check('an implement nobody declares is refused by the schema, in the file that names it',
              any(p['stage'] == 'schema' and p['file'] == 'exercises.yaml' and IMPLEMENT in p['message']
                  for p in result['problems']), result['problems'][:2])
    clash, clash_pkg = stage(VOCABULARY.replace(f'id: {MODALITY}', 'id: power', 1))
    with loader.overlay(clash):
        report = portability.report()
        hit = [c for c in report['collisions'] if c['kind'] == 'modality' and c['id'] == 'power']
        check('a modality that takes a commons id collides with the commons', bool(hit)
              and 'data/commons' in hit[0]['packages'], report['collisions'][:3])
        check('and the commons\' copy is the one read', not loader.load_all_modalities()['power'].get('_package'))


def test_borrowed():
    print('who may name it')
    read = {'owner': {'philosophy': {'id': 'owner'}, 'vocabulary': yaml.safe_load(VOCABULARY)},
            'borrower': {'philosophy': {'id': 'borrower', 'borrows_from': ['owner']}, 'vocabulary': {}},
            'stranger': {'philosophy': {'id': 'stranger'}, 'vocabulary': {}}}
    known = {'modalities': {'power'}, 'movement_patterns': {'squat'}, 'equipment': {'barbell'}}
    check('the package that declares it', MODALITY in portability._known_for('owner', read, known)['modalities'])
    check('a package that borrows from it', MODALITY in portability._known_for('borrower', read, known)['modalities']
          and PATTERN in portability._known_for('borrower', read, known)['movement_patterns'])
    check('nobody else', MODALITY not in portability._known_for('stranger', read, known)['modalities'])
    check('its implements go the same way', IMPLEMENT in portability._known_for('borrower', read, known)['equipment']
          and IMPLEMENT not in portability._known_for('stranger', read, known)['equipment'])
    check('and the commons\' set is not changed by asking', known == {'modalities': {'power'},
                                                                        'movement_patterns': {'squat'},
                                                                        'equipment': {'barbell'}})


def test_in_the_view():
    print('inside the view')
    overlay, pkg = stage()
    commons = set(loader.load_all_modalities())
    with loader.overlay(overlay):
        mods = loader.load_all_modalities()
        check('the modality is read, tagged with its package, after the commons\'',
              set(mods) == commons | {MODALITY} and mods[MODALITY]['_package'] == FIXTURE
              and mods[MODALITY]['recovery_cost'] == 'high')
        check('it rolls up into its family', families.family_of(MODALITY) == 'strength'
              and families.is_strength(MODALITY))
        check('the pattern loads its regions', recovery_regions.pattern_weights([PATTERN]) == {'lower': 1, 'trunk': 0.5})
        check('and beside a commons pattern takes the larger', recovery_regions.pattern_weights([PATTERN, 'rotation'])
              == {'lower': 1, 'trunk': 1})
        flags = loader.load_injury_flags()
        check('the injury flag it names rules it out', PATTERN in flags[FLAG]['excluded_movement_patterns'])
        check('no other flag does', not any(PATTERN in (f.get('excluded_movement_patterns') or [])
                                             for fid, f in flags.items() if fid != FLAG))
        from src import selector
        patterns, _ids = selector._injury_exclusions({'injury_flags': [FLAG]}, flags)
        check('so the selector excludes its exercises for that athlete', PATTERN in patterns)

        from src import package_smoke
        programs = [r['program'] for r in package_smoke.smoke_package(FIXTURE) if r['program']]
        scheduled = {s.get('modality') for raw in programs for w in raw['weeks'] for day in w['schedule'].values()
                     for s in day}
        check('a program schedules the package\'s modality', MODALITY in scheduled, sorted(scheduled))

        from src import equipment
        listed = {e['id']: e for e in equipment.items()}
        check('its implement is in the equipment list, after the commons\', with its package',
              listed[IMPLEMENT] == {'id': IMPLEMENT, 'label': 'Prowler', 'package': FIXTURE}
              and list(listed)[-1] == IMPLEMENT and loader.load_equipment()[-1]['package'] == FIXTURE)
        from src import explore_links
        check('and among what an athlete can declare', IMPLEMENT in explore_links.equipment_vocabulary())
        ex = loader.load_all_exercises()[0]['zz_sled_push']
        check('an athlete without it gets none of its exercises', not selector._equipment_ok(ex, {'barbell', 'sled'})
              and selector._equipment_ok(ex, {IMPLEMENT}))

        import api
        served = {m['id']: m for m in api._all_modalities()}
        check('the API serves it with its display and its package', served[MODALITY]['display']['label'] == 'Sled'
              and served[MODALITY]['_package'] == FIXTURE)
        # The watches and the phone have only the commons compiled in: a session
        # of the package's modality carries how to draw it (roadmap 21.5).
        theirs = next(s for raw in programs for w in raw['weeks'] for day in w['schedule'].values() for s in day
                      if s.get('modality') == MODALITY)
        sent = api.encode_watch_session(theirs, '1-Monday-0')
        own_display = served[MODALITY]['display']
        check('a watch session of its modality carries the display: label, short, colour, icons',
              sent.get('modalityDisplay') == {k: own_display[k] for k in ('label', 'short', 'color', 'icon') if k in own_display}
              and sent['modalityDisplay']['color'].startswith('#'), sent.get('modalityDisplay'))
        check('and with the screen specs too', 'modalityDisplay' in api.encode_watch_session(theirs, '1-Monday-0', spec_level=1))
        common = next((s for raw in programs for w in raw['weeks'] for day in w['schedule'].values() for s in day
                       if s.get('modality') in commons), None)
        check('a session of a commons modality carries none (every build has those)',
              common is None or 'modalityDisplay' not in api.encode_watch_session(common, '1-Tuesday-0'))
        row = next(p for p in portability.report()['packages'] if p['id'] == FIXTURE)
        check('the report finds nothing unknown in the package', not any(v['unknown'] for v in row['vocabulary']),
              row['vocabulary'])

    print('outside it')
    check('no modality', set(loader.load_all_modalities()) == commons)
    check('no family', families.family_of(MODALITY) == 'other')
    check('no pattern', recovery_regions.pattern_weights([PATTERN]) == {})
    check('no exclusion', PATTERN not in loader.load_injury_flags()[FLAG]['excluded_movement_patterns'])
    from src import equipment
    check('no implement', IMPLEMENT not in equipment.ids() and equipment.ids() == [e['id'] for e in equipment.commons_items()])


def test_shipped():
    print('the shipped packages')
    report = portability.report()
    check('every one still names only what it may', all(not any(v['unknown'] for v in p['vocabulary'])
                                                        for p in report['packages']),
          [(p['id'], [v for v in p['vocabulary'] if v['unknown']]) for p in report['packages']
           if any(v['unknown'] for v in p['vocabulary'])])
    check('movement patterns are checked now', any(v['kind'] == 'movement_patterns' and v['count']
                                                   for v in report['packages'][0]['vocabulary']))
    import json
    for name in ('archetype', 'exercise', 'philosophy'):
        with open(os.path.join(ROOT, 'docs', 'schemas', f'{name}.schema.json'), encoding='utf-8') as fh:
            text = json.dumps(json.load(fh))
        check(f'{name}.schema.json no longer invites an undeclared modality or pattern',
              'define a new one' not in text and 'define new ones' not in text and 'introduce new ones' not in text)


def main() -> int:
    test_validator()
    test_gate()
    test_borrowed()
    test_in_the_view()
    test_shipped()
    if FAILURES:
        print(f'{len(FAILURES)} failed')
        return 1
    print('all passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
