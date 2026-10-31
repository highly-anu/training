#!/usr/bin/env python
"""A new package needs no code change: three dropped in, end to end.

Copies three packages — one per engine shape: Wildman (a training contract,
with its own watch screens and source weeks), Horsemen (week templates) and the
test fixture block_fixture (the modality scheduler, which no shipped package
uses any more) — under ids no code has ever seen, into a packages
folder of their own (`TRAINING_PACKAGES_DIR`, src/loader.py), beside the
shipped packages, and runs them through everything a package reaches: schema
validation, the id-collision gate, generation of every track, the API's
philosophies and generate routes, the static reference cache the image
builds, the watch payload with its screens, the program analytics, the source
weeks, the scorecard and `tools/add_package.py --check` — and each copy's own
tests (tests/), which take the package from their folder. Then checks that
nothing in the repository changed.

Each copy takes its own archetype and framework ids (`dx_` before each), as a
new package must: the shipped package it was copied from is beside it.

A package that only these needed — and no edit to src/, api.py, the clients or
the watches — is one the owner can add by writing a folder.

    .venv/bin/python test_package_dropin.py
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.abspath(__file__))
COPIES = {'dropin_contract': 'data/packages/wildman_kettlebell',
          'dropin_templates': 'data/packages/horsemen_gpp',
          'dropin_scheduler': 'test_packages/block_fixture'}
FAILURES: list[str] = []


def check(label: str, condition: bool, detail: str = '') -> None:
    if condition:
        print(f'  ok   {label}')
    else:
        print(f'  FAIL {label} {detail}')
        FAILURES.append(label)


def _own_ids(source: str) -> list[str]:
    """The archetype and framework ids a package declares."""
    import yaml
    ids = []
    for sub in ('archetypes', 'frameworks'):
        for dirpath, _, files in os.walk(os.path.join(source, sub)):
            for name in files:
                if name.endswith('.yaml'):
                    with open(os.path.join(dirpath, name), encoding='utf-8') as fh:
                        ids.append((yaml.safe_load(fh) or {})['id'])
    return ids


def make_packages(folder: str, copies: dict | None = None) -> None:
    """The shipped packages, then each source package under its new id: the
    folder, its own id wherever its files name it (a word, so
    `block_fixture_x` stays), and its archetype and framework ids, files
    included, so none is another package's."""
    for name in sorted(os.listdir(os.path.join(ROOT, 'data', 'packages'))):
        path = os.path.join(ROOT, 'data', 'packages', name)
        if os.path.isdir(path):
            shutil.copytree(path, os.path.join(folder, name))
    for new, source in (copies or COPIES).items():
        old = os.path.basename(source)
        dest = os.path.join(folder, new)
        renames = {old: new, **{i: f'dx_{i}' for i in _own_ids(os.path.join(ROOT, source))}}
        word = re.compile(r'\b(' + '|'.join(sorted(map(re.escape, renames), key=len, reverse=True)) + r')\b')
        # A new package has no records yet (src/package_records.py): the copy
        # starts without the source's, as one written by hand would.
        shutil.copytree(os.path.join(ROOT, source), dest, ignore=shutil.ignore_patterns('records', 'dossier.md'))
        for dirpath, _, files in os.walk(dest):
            for name in files:
                # Its own tests name its own ids too (tests/, which take the
                # package's id from their folder).
                own_test = os.path.basename(dirpath) == 'tests' and name.endswith('.py')
                if not (name.endswith('.yaml') or own_test):
                    continue
                path = os.path.join(dirpath, name)
                with open(path, encoding='utf-8') as fh:
                    text = fh.read()
                with open(path, 'w', encoding='utf-8') as fh:
                    fh.write(word.sub(lambda m: renames[m.group(1)], text))
                stem = name[:-len('.yaml')]
                if not own_test and stem in renames:
                    os.rename(path, os.path.join(dirpath, f'{renames[stem]}.yaml'))


def _status() -> str:
    return subprocess.run(['git', 'status', '--porcelain'], cwd=ROOT, capture_output=True, text=True).stdout


# ── In the child: the packages folder is the copies alone ────────────────────

def child(folder: str) -> int:
    sys.path.insert(0, ROOT)
    from src import goals, loader, provenance, source_weeks, watch_spec
    from src.analytics.context import AnalyticsInputs
    from src.analytics.document import compute_program_analytics
    from src.generator import generate
    from src.validator import validate
    from tools import check_fidelity as cf, validate_entities as ve
    from datetime import date, timedelta

    from src import portability

    print('the packages')
    check('the loader reads the copies, by folder', loader._PACKAGES_DIR == folder)
    phils = {p['id']: p for p in loader.load_philosophies()}
    shipped = {n for n in os.listdir(os.path.join(ROOT, 'data', 'packages'))
               if os.path.isdir(os.path.join(ROOT, 'data', 'packages', n))}
    check('three philosophies under ids no code names, beside the shipped ones',
          set(phils) == set(COPIES) | shipped, str(sorted(set(phils) - shipped)))
    errors = {os.path.relpath(p, folder): e for p, e in ve.validate_path(folder, verbose=False).items() if e}
    check('every file is valid against its schema', not errors, str(errors)[:400])
    collided = portability.id_collisions()
    check('no archetype, framework or media id is another package\'s', not collided, str(collided)[:300])

    print('generation, every track')
    frameworks = loader.load_all_frameworks()
    data = loader.load_all_data()
    programs = {}
    for pkg in sorted(COPIES):
        for track in phils[pkg].get('tracks') or []:
            goal = goals.philosophy_to_goal(pkg, list(frameworks.values()), track_id=track['id'])
            policy = provenance.resolve_source_policy(goal)
            lib = provenance.scope(data, policy)
            constraints = cf.contract_entry(cf.profiles_for(track, frameworks)[0][1], goal.get('training_contract'))
            result = validate(goal, constraints, lib['archetypes'], lib['modalities'], lib['injury_flags'],
                              policy=policy)
            program = generate(goal_id=goal['id'], goal_dict=goal, constraints=constraints, num_weeks=3,
                               output_format='dict', policy=policy) if result.feasible else None
            served = bool(program and program.get('weeks') and not program.get('validation_errors'))
            check(f'{pkg}/{track["id"]} generates', served,
                  str([e.get('code') for e in result.errors] or (program or {}).get('validation_errors'))[:300])
            if served:
                programs[(pkg, track['id'])] = (goal, constraints, program)

    print('the API')
    import api
    client = api.app.test_client()
    listed = {p['id'] for p in client.get('/api/philosophies').get_json()}
    check('GET /api/philosophies lists them', set(COPIES) <= listed, str(sorted(listed)))
    contract_tracks = {t['id']: t.get('entry_requirements') for p in client.get('/api/philosophies').get_json()
                       if p['id'] == 'dropin_contract' for t in p.get('tracks') or []}
    check("a contract's entry requirements name its movements",
          all((r or {}).get('exercise_names', {}).keys() >= set((r or {}).get('mastered_exercises') or [])
              for r in contract_tracks.values()))
    for pkg in sorted(COPIES):
        page = client.get(f'/api/philosophies/{pkg}/describe').get_json() or {}
        weeks = [p['mix'] for t in page.get('tracks') or [] for p in t['phases']]
        grouped = sorted(s for g in page.get('groups') or [] for s in g['sessions'])
        check(f'Explore describes {pkg}: every phase a week, every session grouped',
              bool(weeks) and all(weeks) and grouped == sorted(page.get('sessions') or {}),
              f'{len(weeks)} phases, {len(grouped)} grouped of {len(page.get("sessions") or {})}')
    for pkg in sorted(COPIES):
        (goal, constraints, _), = [v for k, v in programs.items() if k[0] == pkg][:1] or [(None, None, None)]
        if goal is None:
            continue
        resp = client.post('/api/programs/generate', json={
            'philosophy_id': pkg, 'track_id': goal['track']['id'] if isinstance(goal.get('track'), dict) else None,
            'constraints': constraints, 'num_weeks': 2})
        body = resp.get_json() or {}
        check(f'POST /api/programs/generate builds {pkg}', resp.status_code == 200 and bool(body.get('weeks')),
              f'{resp.status_code} {str(body)[:200]}')

    static = os.path.join(folder, '..', 'static')
    manifest = api.build_static(static)
    check('the static reference cache builds, every route answering',
          all(any(f'/api/philosophies/{pkg}/' in k for k in manifest) for pkg in COPIES),
          str(sorted(k for k in manifest if 'philosophies/' in k))[:300])

    print('the watches')
    for (pkg, tid), (_, _, program) in sorted(programs.items()):
        sessions = [s for w in program['weeks'] for ss in w['schedule'].values() for s in ss]
        encoded = [api.encode_watch_session(s, f'1-Monday-{i}', spec_level=1) for i, s in enumerate(sessions)]
        owners = {e['packageId'] for e in encoded}
        bad = [err for e in encoded for k, spec in e['screens'].items()
               for err in watch_spec.resolved_errors(spec, f'{pkg}/{tid}:{k}')]
        check(f'{pkg}/{tid}: every session carries its own screens', owners == {pkg} and not bad,
              f'{owners} {bad[:2]}')
    contract_payload = api.encode_watch_session(
        next(s for (p, _), (_, _, prog) in programs.items() if p == 'dropin_contract'
             for w in prog['weeks'] for ss in w['schedule'].values() for s in ss), 'k', spec_level=1)
    check("the contract package's own watch.yaml reaches the payload",
          contract_payload['watch'].get('label') == watch_spec.session_identity('dropin_contract').get('label')
          and watch_spec.package_spec('dropin_contract'))

    print('analytics')
    start = date(2026, 1, 5)
    for (pkg, tid), (goal, constraints, program) in sorted(programs.items()):
        doc = compute_program_analytics(AnalyticsInputs(
            {'goal': goal, 'constraints': constraints, 'weeks': program['weeks']},
            start, start + timedelta(days=20)))
        ids = {m.get('philosophy') or m.get('id') for m in doc.get('methodologies') or []}
        check(f'{pkg}/{tid}: the analytics document reads its methodology', pkg in ids, str(ids))

    print('the source weeks and the scorecard')
    n, structure, numbers = source_weeks.check('dropin_contract')
    check("the contract package's source weeks reproduce", n and not structure and not numbers,
          str(structure + numbers)[:300])
    from tools import evaluate_packages as ep
    graded = ep.evaluate_package('dropin_scheduler')
    check('the scorecard grades a dropped-in package', graded['tracks']
          and all('E1' in g and 'X2' in g for g in graded['tracks'].values()), str(graded['tracks'])[:200])
    from tools import check_code_neutral as neutral
    check("the neutrality check knows the dropped-in package's ids", 'dropin_scheduler' in neutral.owned_ids())
    shared = ep.package_grades('dropin_scheduler', [], [])
    archetypes = ep._package_archetypes(os.path.join(folder, 'dropin_scheduler'))
    check('its data grades read its own folder', shared['D1'][0] == 'pass' and archetypes
          and 'no archetypes' not in shared['D4'][1], str({k: shared[k] for k in ('D1', 'D3', 'D4')}))

    print('bringing one in')
    done = subprocess.run([sys.executable, os.path.join(ROOT, 'tools', 'add_package.py'), 'dropin_contract',
                           '--check'], cwd=ROOT, capture_output=True, text=True)
    check('tools/add_package.py --check finds nothing to fix', done.returncode == 0
          and 'can be brought in' in done.stdout, (done.stdout + done.stderr)[-600:])

    print('blended with the others')
    from tools import check_styles
    tracks = check_styles.composable_tracks()
    pairs = check_styles.blend_pairs(tracks)
    for pkg in ('dropin_contract', 'dropin_templates'):
        own = [t['key'] for t in tracks if t['philosophy_id'] == pkg]
        paired = {t['key'] for pair in pairs for t in pair if t['philosophy_id'] == pkg}
        check(f'check_styles pairs every track of {pkg}', own and paired == set(own),
              str(sorted(set(own) - paired)))
        pair = next(p for p in pairs if pkg in (p[0]['philosophy_id'], p[1]['philosophy_id']))
        problems, refused = check_styles._compose(*check_styles._blend(*pair))
        check(f"{pair[0]['key']} + {pair[1]['key']} composes", not problems and not refused, problems or refused)
    print()
    if FAILURES:
        print(f'{len(FAILURES)} failure(s)')
        return 1
    print('three packages dropped in: no code changed')
    return 0


# ── In the parent: make the folder, run the child, check the repository ──────

def main() -> int:
    if len(sys.argv) > 2 and sys.argv[1] == '--child':
        return child(sys.argv[2])
    print('the neutrality check reads literals inside interpolations')
    sys.path.insert(0, ROOT)
    from tools.check_code_neutral import _c_literals
    lits = {s for _, s in _c_literals("const a = `${pkg === 'wildman_kettlebell' ? x : 'y'} tail`\n"
                                       'let t = "\\(id == "wk_kb_" ? x : y) end"\n// "bjj"\n')}
    check('a TS ${…} and a Swift \\(…) are code; a comment is not', {'wildman_kettlebell', 'wk_kb_'} <= lits
          and 'bjj' not in lits, str(lits))
    before = _status()
    with tempfile.TemporaryDirectory() as tmp:
        folder = os.path.join(tmp, 'packages')
        os.makedirs(folder)
        make_packages(folder)
        env = {**os.environ, 'TRAINING_PACKAGES_DIR': folder, 'SUPABASE_URL': '', 'DATABASE_URL': ''}
        rc = subprocess.run([sys.executable, os.path.abspath(__file__), '--child', folder], env=env, cwd=ROOT).returncode
        print("each copy's own tests, under its new id")
        tests = sorted(os.path.join(dirpath, n) for new in COPIES
                       for dirpath, _, files in os.walk(os.path.join(folder, new, 'tests'))
                       for n in files if n.startswith('test_') and n.endswith('.py'))
        check('the copies bring tests of their own', any('dropin_contract' in t for t in tests)
              and any('dropin_templates' in t for t in tests), str(tests))
        for test in tests:
            p = subprocess.run([sys.executable, test], env={**env, 'PYTHONPATH': ROOT}, cwd=tmp,
                               capture_output=True, text=True)
            check(os.path.relpath(test, folder), p.returncode == 0, (p.stdout + p.stderr)[-1500:])
    after = _status()
    print('the repository')
    check('nothing outside the packages folder changed', before == after,
          f'\nbefore:\n{before}\nafter:\n{after}')
    return 1 if (rc or FAILURES) else 0


if __name__ == '__main__':
    sys.exit(main())
