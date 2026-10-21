#!/usr/bin/env python
"""A new package needs no code change: three dropped in, end to end.

Copies three packages — one per engine shape: Wildman (a training contract,
with its own watch screens and source weeks), Horsemen (week templates) and ATG
(the modality scheduler) — under ids no code has ever seen, into a packages
folder of their own (`TRAINING_PACKAGES_DIR`, src/loader.py), and runs them
through everything a package reaches: schema validation, generation of every
track, the API's philosophies and generate routes, the watch payload with its
screens, the program analytics, the source weeks and the scorecard. Then checks
that nothing in the repository changed.

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
COPIES = {'dropin_contract': 'wildman_kettlebell', 'dropin_templates': 'horsemen_gpp',
          'dropin_scheduler': 'atg'}
FAILURES: list[str] = []


def check(label: str, condition: bool, detail: str = '') -> None:
    if condition:
        print(f'  ok   {label}')
    else:
        print(f'  FAIL {label} {detail}')
        FAILURES.append(label)


def make_packages(folder: str) -> None:
    """Each source package under its new id: the folder, and its own id
    wherever its files name it (a word, so `atg_split_squat` stays)."""
    for new, old in COPIES.items():
        dest = os.path.join(folder, new)
        shutil.copytree(os.path.join(ROOT, 'data', 'packages', old), dest)
        for dirpath, _, files in os.walk(dest):
            for name in files:
                if name.endswith('.yaml'):
                    path = os.path.join(dirpath, name)
                    with open(path, encoding='utf-8') as fh:
                        text = fh.read()
                    with open(path, 'w', encoding='utf-8') as fh:
                        fh.write(re.sub(rf'\b{re.escape(old)}\b', new, text))


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

    print('the packages')
    check('the loader reads the copies, by folder', loader._PACKAGES_DIR == folder)
    phils = {p['id']: p for p in loader.load_philosophies()}
    check('three philosophies, under ids no code names', set(phils) == set(COPIES), str(sorted(phils)))
    errors = {os.path.relpath(p, folder): e for p, e in ve.validate_path(folder, verbose=False).items() if e}
    check('every file is valid against its schema', not errors, str(errors)[:400])

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
        (goal, constraints, _), = [v for k, v in programs.items() if k[0] == pkg][:1] or [(None, None, None)]
        if goal is None:
            continue
        resp = client.post('/api/programs/generate', json={
            'philosophy_id': pkg, 'track_id': goal['track']['id'] if isinstance(goal.get('track'), dict) else None,
            'constraints': constraints, 'num_weeks': 2})
        body = resp.get_json() or {}
        check(f'POST /api/programs/generate builds {pkg}', resp.status_code == 200 and bool(body.get('weeks')),
              f'{resp.status_code} {str(body)[:200]}')

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
    before = _status()
    with tempfile.TemporaryDirectory() as tmp:
        folder = os.path.join(tmp, 'packages')
        os.makedirs(folder)
        make_packages(folder)
        env = {**os.environ, 'TRAINING_PACKAGES_DIR': folder, 'SUPABASE_URL': '', 'DATABASE_URL': ''}
        rc = subprocess.run([sys.executable, os.path.abspath(__file__), '--child', folder], env=env, cwd=ROOT).returncode
    after = _status()
    print('the repository')
    check('nothing outside the packages folder changed', before == after,
          f'\nbefore:\n{before}\nafter:\n{after}')
    return 1 if (rc or FAILURES) else 0


if __name__ == '__main__':
    sys.exit(main())
