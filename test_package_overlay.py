#!/usr/bin/env python
"""The loader's two roots (docs/roadmap.md 20.3): the shipped packages, and
for the caller in context an overlay of its own.

Runs on the repository's packages, unchanged, with overlays in scratch
folders: the modality scheduler's fixture as a package of the caller's own, a
copy of a shipped package that keeps its ids, a folder named as a shipped
package, and one that does not load. In one interpreter, as a server is:

  - without an overlay the loader returns exactly what it did;
  - an overlay adds its packages for that caller and no other, and the gate
    (src/package_gate.py) and a generation run on them;
  - it never replaces a shipped framework, archetype or philosophy;
  - a package that does not load is set aside alone;
  - what modules keep is kept per view, and one call forgets it;
  - a reused thread sees nothing of the caller before it.

Run: SUPABASE_URL='' .venv/bin/python test_package_overlay.py
"""
from __future__ import annotations

import atexit
import hashlib
import json
import os
import re
import shutil
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

os.environ.setdefault('SUPABASE_URL', '')
os.environ.setdefault('DATABASE_URL', '')
os.environ.pop('TRAINING_PACKAGES_DIR', None)   # the repository's packages are the shipped root

ROOT = os.path.dirname(os.path.abspath(__file__))
FIXTURE = 'block_fixture'

from src import explore_philosophy, loader, package_gate, session_icon, watch_spec  # noqa: E402
from src.analytics import benchmarks_data  # noqa: E402

FAILURES: list[str] = []


def check(label: str, condition: bool, detail='') -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        FAILURES.append(label)


def scratch() -> str:
    folder = tempfile.mkdtemp(prefix='overlay-')
    atexit.register(shutil.rmtree, folder, True)
    return folder


def fingerprint() -> str:
    """Everything the loader returns, in its order."""
    ex, by = loader.load_all_exercises()
    out = {
        'fw': list(loader.load_all_frameworks().items()), 'arch': loader.load_all_archetypes(),
        'ex': list(ex.items()), 'by': [(k, list(v.items())) for k, v in by.items()],
        'seeds': [(k, {lv: sorted(s) for lv, s in v.items()}) for k, v in loader.load_level_seeds().items()],
        'an': list(loader.load_analytics_specs().items()), 'watch': list(loader.load_watch_specs().items()),
        'phil': loader.load_philosophies(), 'media': list(loader.load_exercise_media().items()),
    }
    return hashlib.sha256(json.dumps(out, default=str).encode()).hexdigest()


def shipped_slice() -> str:
    """The shipped packages' part of what the loader returns: nothing an
    overlay adds may change it."""
    shipped = {name for name, _ in loader._shipped_dirs()}
    ex, by = loader.load_all_exercises()
    fw = loader.load_all_frameworks()
    out = {
        'fw': [(k, v) for k, v in fw.items() if v.get('source_philosophy') in shipped],
        'arch': [a for a in loader.load_all_archetypes() if a['_package'] in shipped],
        'by': [(k, list(v.items())) for k, v in by.items() if k in shipped],
        'phil': [p for p in loader.load_philosophies() if p['id'] in shipped],
    }
    return hashlib.sha256(json.dumps(out, default=str).encode()).hexdigest()


def stage(overlay: str, *, fixture=True, copy_of=None, shadow=None, broken=False) -> None:
    if fixture:
        shutil.copytree(os.path.join(ROOT, 'test_packages', FIXTURE), os.path.join(overlay, FIXTURE))
    if copy_of:   # a shipped package under a new name, its framework and archetype ids kept
        dest = os.path.join(overlay, f'zz_{copy_of}_copy')
        shutil.copytree(os.path.join(ROOT, 'data', 'packages', copy_of), dest)
        path = os.path.join(dest, 'philosophy.yaml')
        text = open(path, encoding='utf-8').read()
        open(path, 'w', encoding='utf-8').write(re.sub(rf'^id: {copy_of}$', f'id: zz_{copy_of}_copy', text, flags=re.M))
    if shadow:    # a folder named as a shipped package
        shutil.copytree(os.path.join(ROOT, 'test_packages', FIXTURE), os.path.join(overlay, shadow))
    if broken:
        dest = os.path.join(overlay, 'zz_broken')
        shutil.copytree(os.path.join(ROOT, 'test_packages', FIXTURE), dest)
        path = os.path.join(dest, 'philosophy.yaml')
        text = open(path, encoding='utf-8').read()
        open(path, 'w', encoding='utf-8').write(re.sub(rf'^id: {FIXTURE}$', 'id: zz_broken', text, flags=re.M))
        with open(os.path.join(dest, 'frameworks', 'zz_no_id.yaml'), 'w', encoding='utf-8') as fh:
            fh.write('name: A framework with no id\nsessions_per_week: {}\n')


def ids() -> set:
    return {p['id'] for p in loader.load_philosophies()}


def test_shipped_unchanged():
    print('without an overlay')
    check('no overlay is named', loader.overlay_dir() is None and loader.overlay_packages() == []
          and loader.quarantined() == [])
    check('the packages are the shipped ones', ids() == {name for name, _ in loader._shipped_dirs()}, sorted(ids()))
    check('package_dir finds each, and says where a missing one would be',
          all(os.path.isdir(loader.package_dir(i)) for i in ids())
          and loader.package_dir('zz_none') == os.path.join(loader._PACKAGES_DIR, 'zz_none'))


def test_adds_for_its_caller():
    print("an overlay adds its packages, for its caller")
    before, shipped = fingerprint(), shipped_slice()
    mine = scratch()
    stage(mine)
    with loader.overlay(mine):
        check('its package is there', FIXTURE in ids() and loader.overlay_packages() == [FIXTURE])
        check('after the shipped ones', [p['id'] for p in loader.load_philosophies()][-1] == FIXTURE)
        check('with its frameworks, archetypes and exercises',
              any(a['_package'] == FIXTURE for a in loader.load_all_archetypes())
              and FIXTURE in loader.load_all_exercises()[1]
              and bool(loader.load_philosophy(FIXTURE)['system_connections']['frameworks']))
        check('the shipped packages read as they did', shipped_slice() == shipped)
        result = package_gate.check_package(os.path.join(mine, FIXTURE))
        check('the gate runs every stage on it and it generates', result['ok']
              and result['ran'] == list(package_gate.STAGES), {'problems': result['problems'][:3],
                                                               'skipped': result['skipped']})
        loose = package_gate.check_package(os.path.join(mine, FIXTURE), smoke=False, owner_prefix='u1a2b3c4d_')
        named = {p['message'].split("'")[1] for p in loose['problems'] if p['code'] == 'not_prefixed'}
        own_fw = set(loader.load_philosophy(FIXTURE)['system_connections']['frameworks'])
        with loader.overlay(None):
            shipped_ex = set(loader.load_all_exercises()[0])
        check("as an athlete's own, every id it declares must carry the owner's prefix",
              FIXTURE in named and own_fw <= named and not (named & shipped_ex), sorted(named)[:6])
        check('an exercise a shipped package declares needs none',
              any(e in shipped_ex for e in loader.load_all_exercises()[1][FIXTURE]))
        other = scratch()
        with loader.overlay(other):
            check("another caller's (empty) overlay, nested, sees none of it", FIXTURE not in ids())
        check('and the first is back after it', FIXTURE in ids())
    check('gone when the block ends', FIXTURE not in ids() and loader.overlay_dir() is None)
    check('and the loader returns exactly what it did', fingerprint() == before)
    outside = package_gate.check_package(os.path.join(mine, FIXTURE))
    check('outside its overlay the gate does not pretend to have checked it',
          not outside['ok'] and [s['stage'] for s in outside['skipped']] == ['ids', 'smoke', 'provenance'])


def test_never_replaces():
    print('an overlay never replaces what is shipped')
    shipped = shipped_slice()
    atg_fw = {k: v for k, v in loader.load_all_frameworks().items() if v.get('source_philosophy') == 'atg'}
    media = dict(loader.load_exercise_media())
    mine = scratch()
    stage(mine, fixture=False, copy_of='atg', shadow='crossfit')
    with loader.overlay(mine):
        check('a copy that keeps a shipped package\'s ids loads as a package', 'zz_atg_copy' in ids())
        check('the shipped frameworks stay the shipped copies',
              all(loader.load_all_frameworks()[k] == v for k, v in atg_fw.items()))
        check('and stay their philosophy\'s', sorted(loader.load_philosophy('atg')['system_connections']['frameworks'])
              == sorted(atg_fw))
        check('the copy gets none of them', loader.load_philosophy('zz_atg_copy')['system_connections']['frameworks'] == [])
        check('every shipped archetype is still its package\'s',
              not any(a['_package'] == 'zz_atg_copy' for a in loader.load_all_archetypes()))
        check('shipped media is not replaced', all(loader.load_exercise_media().get(k) == v for k, v in media.items()))
        check('the shipped packages read as they did', shipped_slice() == shipped)
        set_aside = {q['package']: q['problem'] for q in loader.quarantined()}
        check('a folder named as a shipped package is set aside', 'crossfit' in set_aside
              and 'shipped' in set_aside['crossfit'], set_aside)
        check('and the shipped one is the one read', loader.package_dir('crossfit').startswith(loader._PACKAGES_DIR))
        result = package_gate.check_package(os.path.join(mine, 'zz_atg_copy'), smoke=False)
        check('the gate refuses the copy for its ids', any(p['code'] == 'collision' for p in result['problems']),
              result['problems'][:2])


def test_quarantine():
    print('a package that does not load')
    shipped = shipped_slice()
    mine = scratch()
    stage(mine, broken=True)
    with loader.overlay(mine):
        set_aside = loader.quarantined()
        check('is set aside, with why', [q['package'] for q in set_aside] == ['zz_broken']
              and 'no id' in set_aside[0]['problem'], set_aside)
        check('none of it is read', 'zz_broken' not in ids()
              and not any(a['_package'] == 'zz_broken' for a in loader.load_all_archetypes())
              and 'zz_broken' not in loader.load_all_exercises()[1])
        check('the package beside it loads', FIXTURE in ids())
        check('and the shipped packages read as they did', shipped_slice() == shipped)
        ok = package_gate.check_package(os.path.join(mine, FIXTURE), smoke=False)
        check('the gate still answers for the good one', not ok['problems'], ok['problems'])
    unparsable = scratch()
    os.makedirs(os.path.join(unparsable, 'zz_bad'))
    open(os.path.join(unparsable, 'zz_bad', 'philosophy.yaml'), 'w', encoding='utf-8').write('id: [unclosed\n')
    with loader.overlay(unparsable):
        check('a file that does not parse sets its package aside, and nothing raises',
              [q['package'] for q in loader.quarantined()] == ['zz_bad'] and 'zz_bad' not in ids())


def test_kept_per_view():
    print('what modules keep is kept per view')
    mine = scratch()
    stage(mine)
    glances = len(explore_philosophy.glance_all())
    owners = len(watch_spec._owners())
    icons = len(session_icon._archetypes())
    standards = len(benchmarks_data.load_benchmarks())
    with loader.overlay(mine):
        check('Explore\'s glances include the caller\'s package', len(explore_philosophy.glance_all()) == glances + 1
              and explore_philosophy.describe(FIXTURE) is not None)
        check('the watch\'s owners and the icons too', len(watch_spec._owners()) > owners
              and len(session_icon._archetypes()) > icons)
        check('a standard list is the caller\'s view', len(benchmarks_data.load_benchmarks()) == standards)
    check('and the shipped view is as it was', len(explore_philosophy.glance_all()) == glances
          and explore_philosophy.describe(FIXTURE) is None and len(watch_spec._owners()) == owners
          and len(session_icon._archetypes()) == icons)
    with loader.overlay(mine):
        check('the caller\'s view is still kept', len(explore_philosophy.glance_all()) == glances + 1)

    print('an overlay directory is read once; a changed set is a new directory')
    with loader.overlay(mine):
        shutil.copytree(os.path.join(mine, FIXTURE), os.path.join(mine, 'zz_later'))
        path = os.path.join(mine, 'zz_later', 'philosophy.yaml')
        text = open(path, encoding='utf-8').read()
        open(path, 'w', encoding='utf-8').write(re.sub(rf'^id: {FIXTURE}$', 'id: zz_later', text, flags=re.M))
        check('a folder added to it is not seen', 'zz_later' not in ids())
        loader.forget_overlay(mine)
        check('until the directory is forgotten', 'zz_later' in ids())
        loader.invalidate_package_data()
        check('one call forgets everything kept, in every view',
              not loader._SHIPPED_STORES and not loader._OVERLAY_STORES and not loader._OVERLAY_PACKAGES)
        check('and it is read again', 'zz_later' in ids() and len(explore_philosophy.glance_all()) == glances + 2)

    print('only the most recent overlays are kept')
    for _ in range(loader._MAX_OVERLAY_VIEWS + 3):
        with loader.overlay(scratch()):
            explore_philosophy.glance_all()
    check('bounded', len(loader._OVERLAY_STORES) == loader._MAX_OVERLAY_VIEWS, len(loader._OVERLAY_STORES))
    check('the shipped view is never dropped', len(explore_philosophy.glance_all()) == glances)


def test_threads():
    print('a reused thread')
    mine = scratch()
    stage(mine)

    def with_overlay():
        with loader.overlay(mine):
            return FIXTURE in ids()

    def without():
        return loader.overlay_dir(), FIXTURE in ids()

    with ThreadPoolExecutor(max_workers=1) as pool:   # one thread, as a server's reused worker
        first = pool.submit(with_overlay).result()
        after = pool.submit(without).result()
    check('saw its caller\'s package', first)
    check('and nothing of it for the next caller', after == (None, False), after)
    with loader.overlay(mine):
        with ThreadPoolExecutor(max_workers=1) as pool:
            fresh = pool.submit(without).result()
    check('a thread started inside a view does not inherit it', fresh == (None, False), fresh)


def test_generation_unchanged():
    print('a shipped program is the same inside an overlay')
    from src import goals
    from src.generator import generate
    from src.package_eval import ALL_EQUIPMENT

    def program() -> str:
        frameworks = list(loader.load_all_frameworks().values())
        goal = goals.philosophy_to_goal('crossfit', frameworks)
        raw = generate(goal_id=goal['id'], goal_dict=goal, num_weeks=3, output_format='dict', constraints={
            'days_per_week': 5, 'session_time_minutes': 60, 'training_level': 'intermediate',
            'equipment': ALL_EQUIPMENT, 'injury_flags': [], 'periodization_week': 1, 'fatigue_state': 'normal'})
        return hashlib.sha256(json.dumps(raw.get('weeks'), sort_keys=True, default=str).encode()).hexdigest()

    plain = program()
    mine = scratch()
    stage(mine, copy_of='atg')
    with loader.overlay(mine):
        check('week for week', program() == plain)


# Where the shipped root may still be named: the authoring routes write there,
# the gate lists the roots it accepts, and the push gates' records and fidelity
# files are a checkout's.
_ROOT_USERS = {'api.py': 1, 'src/package_gate.py': 2, 'src/package_records.py': 1, 'src/package_fidelity.py': 1,
               'src/portability.py': 1}


def test_no_module_joins_the_root():
    print('no module reaches a package by joining the shipped root')
    import glob
    found = {}
    for path in ['api.py'] + sorted(glob.glob(os.path.join(ROOT, 'src', '**', '*.py'), recursive=True)):
        rel = os.path.relpath(os.path.join(ROOT, path), ROOT).replace(os.sep, '/')
        if rel == 'src/loader.py':
            continue
        n = len(re.findall(r'(?<![A-Za-z])_PACKAGES_DIR', open(os.path.join(ROOT, rel), encoding='utf-8').read()))
        if n:
            found[rel] = n
    check('loader.package_dirs / package_dir / package_files instead (the known uses are listed here)',
          found == _ROOT_USERS, found)


def main() -> int:
    test_no_module_joins_the_root()
    test_shipped_unchanged()
    test_adds_for_its_caller()
    test_never_replaces()
    test_quarantine()
    test_kept_per_view()
    test_threads()
    test_generation_unchanged()
    if FAILURES:
        print(f'{len(FAILURES)} failed')
        return 1
    print('all passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
