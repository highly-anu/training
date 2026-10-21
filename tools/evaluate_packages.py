#!/usr/bin/env python
"""The package scorecard, and the gate that holds it.

For every philosophy x track, generates the fidelity profiles
(tools/check_fidelity.py: the ideal athlete, the lowest and highest days, a
kettlebell home, bodyweight, 45 minutes, two injuries) and, in the same pass,
the scorecard's own: every level the track is not already generated at, a
knee flag, three days, 30 minutes and one bell, eight weeks each. A refused
constrained profile is probed with each constraint lifted alone
(src/constraint_impact), two weeks each, to say whether one would unblock it.

Each package x track is graded on six dimensions, every criterion pass,
partial or fail (src/package_eval.py; docs/package-fidelity/README.md has
the table), and `audited` is derived: every criterion that is not hygiene
passes on every track the package does not exclude. The Source criteria
read each package's record (data/packages/<id>/fidelity.yaml,
src/package_fidelity.py), and docs/package-fidelity/status.yaml is written
from the records and the grades (--update-baseline), never by hand.

Usage:
  .venv/bin/python tools/evaluate_packages.py                       # gate
  .venv/bin/python tools/evaluate_packages.py --package bjj
  .venv/bin/python tools/evaluate_packages.py --report docs/package-fidelity/scorecard.md
  .venv/bin/python tools/evaluate_packages.py --update-baseline
  .venv/bin/python tools/evaluate_packages.py --update-baseline --accept-worse   # a stricter grader

Exits 1 when a grade is worse than tools/scorecard_baseline.json records, a
package x track x criterion is new, a fidelity finding is not in
tools/fidelity_baseline.json (tools/check_fidelity.gate, run here), an
exercise is newly orphaned (tools/check_exercise_coverage, run here; D2 reads
it), status.yaml is not what the records and the grades write — or a
baseline is stale: a better grade, a finding that stopped firing or an
exercise no longer orphaned is recorded in the change that earns it, or the
next change may lose it unnoticed. --update-baseline records better grades
(and writes status.yaml) and refuses worse ones; --accept-worse records them
too, for a grader made stricter.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from collections import defaultdict
from concurrent.futures import ProcessPoolExecutor
from datetime import date, timedelta

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
os.environ.setdefault('SUPABASE_URL', '')

import yaml  # noqa: E402

from src import constraint_impact, loader, package_eval as pe, package_fidelity as pf, source_weeks  # noqa: E402
from src.analytics import spec as spec_mod, vocabulary  # noqa: E402
from src.generator import generate  # noqa: E402
from src.validator import validate  # noqa: E402
from tools import check_code_neutral as neutral, check_exercise_coverage as coverage, check_fidelity as cf  # noqa: E402

BASELINE = os.path.join(ROOT, 'tools', 'scorecard_baseline.json')
STATUS = os.path.join(ROOT, 'docs', 'package-fidelity', 'status.yaml')
EVAL_WEEKS = 8
PROBE_WEEKS = 2
# The fidelity profiles that constrain the athlete, and the scorecard's own.
ROBUST = ('bodyweight', 'kb-home', '45min', 'lumbar-disc', 'shoulder',
          'eval-knee', 'eval-3d', 'eval-30min', 'eval-one-bell')


# ── Profiles ──────────────────────────────────────────────────────────────────

_EXERCISES: dict = {}


def _exercises() -> dict:
    if not _EXERCISES:
        _EXERCISES.update(loader.load_all_data()['exercises'])
    return _EXERCISES


def extra_profiles(phil: dict, track: dict, goal: dict, base: dict) -> list:
    weeks = min(EVAL_WEEKS, sum(int(p.get('weeks') or 1) for p in track['phases']))
    opts = {'weeks': weeks, 'fidelity': False}
    contract = goal.get('training_contract')
    generated = {base['training_level']} | set((contract or {}).get('training_levels') or [])
    out = [(f'eval-level-{lv}', {**base, 'training_level': lv}, opts)
           for lv in pe.LEVELS if lv not in generated]
    out.append(('eval-knee', {**base, 'injury_flags': ['patellar_tendinopathy']}, opts))
    if base['days_per_week'] != 3:
        out.append(('eval-3d', {**base, 'days_per_week': 3}, opts))
    out.append(('eval-30min', {**base, 'session_time_minutes': 30}, opts))
    exercises = _exercises()
    if any('kettlebell' in (exercises.get(e) or {}).get('equipment', [])
           for m in (contract or {}).get('modules') or [] for b in m.get('blocks') or []
           for e in [b.get('exercise_id')] + list(b.get('alternatives') or [])):
        out.append(('eval-one-bell', {**base, 'kettlebell_count': 1}, opts))
    return out


def _serves(rec: dict, constraints: dict) -> bool:
    goal, lib, policy = rec['goal'], rec['lib'], rec['policy']
    result = validate(goal, constraints, lib['archetypes'], lib['modalities'], lib['injury_flags'], policy=policy)
    if not result.feasible:
        return False
    program = generate(goal_id=goal['id'], goal_dict=goal, constraints=constraints,
                       num_weeks=PROBE_WEEKS, output_format='dict', policy=policy)
    return not pe.refused(program)


def _unblocked(rec: dict) -> bool:
    """Would lifting one constraint alone (or the framework's ideal days and
    minutes) let the refused request generate?"""
    constraints = rec['constraints']
    first = rec['frameworks'].get(rec['track']['phases'][0]['framework_id'])
    level = constraints.get('training_level')
    reference = constraint_impact.reference_constraints(
        constraints, rec['lib'], first, requirements=constraint_impact.contract_requirements(rec['goal'], level))
    runs = constraint_impact.relaxations(constraints, reference)
    probe = constraint_impact.schedule_probe(constraints, first)
    if probe:
        runs['schedule'] = probe
    return any(_serves(rec, c) for c in runs.values())


# ── Per track ─────────────────────────────────────────────────────────────────

def _lead(rec: dict) -> tuple[str | None, str | None]:
    """The analytics headline (id, primitive) of the ideal program."""
    from src.analytics.context import AnalyticsInputs
    from src.analytics.document import compute_program_analytics
    program = rec['program']
    start = date(2026, 1, 5)
    doc = compute_program_analytics(AnalyticsInputs(
        {'goal': rec['goal'], 'constraints': rec['constraints'], 'weeks': program['weeks']},
        start, start + timedelta(days=7 * 3 + 2)))
    if not doc.get('methodologies'):
        return None, None
    lead = doc['methodologies'][0].get('headlineId')
    prim = next((p['primitive'] for p in doc.get('progress') or [] if p['id'] == lead), None)
    return lead, prim


def _standards_known() -> tuple[set, dict]:
    """Every commons standard id, and each one's derived_from lifts."""
    known, derived = set(), {}
    for name in sorted(os.listdir(os.path.join(ROOT, 'data', 'benchmarks'))):
        if not name.endswith('.yaml') or name == 'cell_standards.yaml':
            continue
        with open(os.path.join(ROOT, 'data', 'benchmarks', name)) as fh:
            for item in yaml.safe_load(fh) or []:
                known.add(item['id'])
                derived[item['id']] = set((item.get('derived_from') or {}).get('exercises') or [])
    return known, derived


def _declared_standards(pkg: str, track: dict) -> tuple[list, set]:
    """The standards a package's analytics declares for this track, and the
    ones it marks for manual entry."""
    raw = spec_mod.declared(pkg) or {}
    track_fws = {ph['framework_id'] for ph in track['phases']}
    ids, manual = [], set()
    for item in raw.get('benchmarks') or []:
        bid = item['id'] if isinstance(item, dict) else item
        if isinstance(item, dict) and item.get('frameworks') and not set(item['frameworks']) & track_fws:
            continue
        ids.append(bid)
        if isinstance(item, dict) and item.get('manual'):
            manual.add(bid)
    for entry in raw.get('progress') or []:
        fws = set((entry.get('scope') or {}).get('frameworks') or [])
        if entry.get('primitive') == 'benchmark_level' and (not fws or fws & track_fws):
            ids += [b for b in entry.get('benchmarks') or [] if b not in ids]
    return ids, manual


def grade_track(pkg: str, track: dict, recs: dict, fid_rows: list, record: dict | None) -> dict:
    """`record`: the package's fidelity.yaml (None without one)."""
    refs = pf.refs(record)
    ideal_name = next(p for p in recs if p.startswith('ideal-'))
    ideal = recs[ideal_name]
    goal, frameworks = ideal['goal'], ideal['frameworks']
    contract = goal.get('training_contract')
    written = pe.written_levels(track, frameworks, contract)
    base_level = ideal['constraints']['training_level']

    def level_of(name: str) -> str | None:
        if name.startswith(('level-', 'eval-level-')):
            return name.rsplit('-', 1)[1]
        return None

    qualified = {}
    other_levels = {}
    for name, rec in recs.items():
        lv = level_of(name)
        if lv and lv not in written:
            other_levels[lv] = pe.refused(rec['program'], rec['validation'])
            continue
        if name.startswith(('ideal-', 'level-', 'eval-level-')) or name.rstrip('d').isdigit():
            if not pe.refused(rec['program'], rec['validation']):
                qualified[name] = rec['program']
    grades = {}
    grades['E1'] = pe.grade_e1(qualified)
    grades['E2'] = pe.grade_e2(qualified)
    grades['E3'] = pe.grade_e3(other_levels)
    concentration = [] if pe.refused(ideal['program'], ideal['validation']) else pe.concentration(
        ideal['program'], track, ideal['lib']['archetypes'], base_level, set(ideal['constraints']['equipment']),
        refs)
    grades['E4'] = pe.grade_e4(concentration)
    broken = [b for prog in qualified.values() for b in pe.claims_broken(prog, track)]
    broken += [f"{r['profile']}: {r['finding']['detail']}" for r in fid_rows
               if r['finding']['rule'] in pe.CLAIM_RULES and r['finding']['severity'] in ('error', 'warn')]
    grades['E5'] = pe.grade_e5(pe.declares_claims(track, contract, refs), broken)
    grades['E6'] = pe.grade_e6([r['finding'] for r in fid_rows if r['finding']['severity'] in ('error', 'warn')])

    outcomes = {}
    for name in ROBUST:
        rec = recs.get(name)
        if rec is None:
            continue
        served = not pe.refused(rec['program'], rec['validation'])
        unblocked = None if served else _unblocked(rec)
        # The fidelity rules on this athlete — the scorecard's own profiles
        # are not in the fidelity gate's run, so they are read here.
        rows = [r for r in fid_rows if r['profile'] == name] if rec['fidelity'] else \
            (cf.fidelity_rows(rec) if served else [])
        errors = [r['finding'] for r in rows if r['finding']['severity'] == 'error']
        outcomes[name] = pe.robustness_outcome(rec['program'], rec['validation'], track, unblocked, errors)
    grades['R1'] = pe.grade_r1(outcomes)

    lead, prim = (None, None) if pe.refused(ideal['program'], ideal['validation']) else _lead(ideal)
    currency, currency_rule = pf.currency(record, track['id'])
    grades['M1'] = pe.grade_m1(currency, lead, currency_rule)
    grades['M2'] = pe.grade_m2(prim, vocabulary.PRIMITIVES, vocabulary.CAPTURE)
    known, derived = _standards_known()
    declared, manual = _declared_standards(pkg, track)
    # Entered by hand only where a rule says the source gives no session for it.
    manual = {b for b in manual if pf.manual_cited(record, b)}
    prescribed = {ea['exercise']['id'] for _, s in pe.sessions(ideal['program']) for ea in s.get('exercises') or []
                  if ea.get('exercise')}
    tested = {ea['standard']['id'] for w in (ideal['program'] or {}).get('weeks') or []
              for day in w['schedule'].values() for s in day for ea in s.get('exercises') or []
              if isinstance(ea.get('standard'), dict) and ea['standard'].get('id')}
    estimated = {b for b in declared if derived.get(b, set()) & prescribed}
    grades['M3'] = pe.grade_m3(declared, tested, estimated, manual)
    grades['M4'] = pe.grade_m4(set(declared) | tested, known)
    grades['X2'] = pe.grade_x2(*_watch_screens(ideal['program']))
    return {c: list(g) for c, g in grades.items()}


def _watch_screens(program: dict | None) -> tuple[list[str], list[str]]:
    """(screen errors, generic-screen steps) of every step of a program, each
    encoded by the watches' own encoder (api.encode_watch_session, ?spec=1):
    the steps it sends, meta blocks included, with the slot type it infers."""
    import api
    from src import watch_spec
    known = set(watch_spec.vocabulary()['defaults']['slot_types'])
    errors, fallbacks = [], []
    for i, (_, s) in enumerate(pe.sessions(program)):
        payload = api.encode_watch_session(s, f'scorecard-{i}', spec_level=1)
        aid = payload.get('archetypeId')
        for k, spec in payload['screens'].items():
            errors += [e for e in watch_spec.resolved_errors(spec, f'{aid}:{k}') if e not in errors]
        for step in payload['exercises']:
            slot_type = step.get('slotType')
            if slot_type not in known and not any(f.startswith(f'{slot_type} ') for f in fallbacks):
                fallbacks.append(f"{slot_type} ({aid}:{step.get('slotRole')})")
    return errors, fallbacks


def evaluate_package(pkg: str) -> dict:
    """Fidelity rows and the per-track execution, robustness and measurement grades."""
    record = pf.load(pkg)
    by_track: dict = defaultdict(dict)
    rows_by_track: dict = defaultdict(list)
    tracks = {}
    for rec in cf.iter_programs(pkg, extra_profiles):
        tid = rec['track']['id']
        tracks[tid] = rec['track']
        if rec['fidelity']:
            rows_by_track[tid] += cf.fidelity_rows(rec)
        by_track[tid][rec['profile']] = rec
    out = {'fidelity_rows': [r for rows in rows_by_track.values() for r in rows], 'tracks': {}}
    # S5 per track, from the source weeks written for it: one track's week
    # reproducing says nothing of another's.
    weeks = source_weeks.check_by_track(pkg)
    in_ci = pf.tests_in_ci(pkg, record)
    for tid, recs in by_track.items():
        out['tracks'][tid] = grade_track(pkg, tracks[tid], recs, rows_by_track[tid], record)
        out['tracks'][tid]['S5'] = list(pe.grade_s5(*weeks.get(tid, (0, [], [])), in_ci,
                                                    pf.invented_track(record, tid)))
    return out


# ── Per package ──────────────────────────────────────────────────────────────

def package_grades(pkg: str, orphans: list[str], named: list[str]) -> dict:
    """Source, data and X1: the same for every track of the package (S5 is
    the track's). `orphans`: its catalog exercises no program reaches;
    `named`: code literals that name it — both computed in this run."""
    from tools import validate_entities as ve
    record = pf.load(pkg)
    text = pf.dossier(pkg)
    grades = {
        'S1': pe.grade_s1(record, text is not None),
        'S2': pe.grade_s2(pf.sources_kind(record), record),
        'S3': pe.grade_s3(record, pf.debt(record), pf.ref_errors(pkg, record)),
        'S4': pe.grade_s4(record, pf.citation_errors(pkg, record, text)),
        'S6': pe.grade_s6(record),
    }
    pkg_dir = os.path.join(loader._PACKAGES_DIR, pkg)
    errors = [f"{os.path.relpath(p, ROOT)}: {e}" for p, errs in ve.validate_path(pkg_dir, verbose=False).items()
              for e in errs or []]
    errors += [f"injury_flags.yaml: {e}" for e in ve.validate_file(
        os.path.join(ROOT, 'data', 'commons', 'constraints', 'injury_flags.yaml'), verbose=False)]
    grades['D1'] = pe.grade_d1(errors)
    grades['D2'] = pe.grade_d2(orphans)
    grades['X1'] = pe.grade_x1(named)
    _, catalogs = loader.load_all_exercises()
    catalog = catalogs.get(pkg) or {}
    media_path = os.path.join(pkg_dir, 'exercise_media.yaml')
    media = set()
    if os.path.exists(media_path):
        with open(media_path) as fh:
            media = set((yaml.safe_load(fh) or {}).keys())
    grades['D3'] = pe.grade_d3(len(media & catalog.keys()), len(catalog))
    archetypes = _package_archetypes(pkg_dir)
    grades['D4'] = pe.grade_d4(
        sum(1 for e in catalog.values() if not e.get('movement_patterns')),
        sum(1 for a in archetypes if not a.get('training_levels')),
        sum(1 for a in archetypes if ((a.get('scaling') or {}).get('equipment_limited'))))
    return {c: list(g) for c, g in grades.items()}


def _package_archetypes(pkg_dir: str) -> list:
    out = []
    for dirpath, _, files in os.walk(os.path.join(pkg_dir, 'archetypes')):
        for name in sorted(files):
            if name.endswith('.yaml'):
                with open(os.path.join(dirpath, name)) as fh:
                    out.append(yaml.safe_load(fh) or {})
    return out


# ── The run ──────────────────────────────────────────────────────────────────

def run(packages: list[str]) -> tuple[dict, list, dict]:
    """(scorecard, fidelity rows, package -> orphaned exercises)."""
    scorecard: dict = {}
    fid_rows: list = []
    reach_for = sorted(coverage.borrowers_of(packages))
    with ProcessPoolExecutor() as pool:
        evaluated = pool.map(evaluate_package, packages)
        reaches = pool.map(coverage.reach_of, reach_for)
        results = dict(zip(packages, evaluated))
        reached = dict(zip(reach_for, reaches))
    _, catalogs = loader.load_all_exercises()
    borrowers = coverage._borrowers(loader.load_philosophies())
    orphans = {pkg: coverage.orphans_of(pkg, reached, catalogs, borrowers) for pkg in packages}
    named = neutral.by_package(neutral.scan())
    for pkg in packages:
        res = results[pkg]
        shared = package_grades(pkg, orphans[pkg], named.get(pkg, []))
        fid_rows += res['fidelity_rows']
        scorecard[pkg] = {tid: {**shared, **g} for tid, g in res['tracks'].items()}
    return scorecard, fid_rows, orphans


def derive(pkg: str, tracks: dict) -> str:
    record = pf.load(pkg)
    has_dossier = record is not None and pf.dossier(pkg) is not None
    return pe.derived_status({t: {c: tuple(g) for c, g in crit.items()} for t, crit in tracks.items()},
                             set((record or {}).get('excluded_tracks') or {}), has_dossier)


def status_text(scorecard: dict) -> str:
    """docs/package-fidelity/status.yaml as this run's grades write it."""
    return pf.status_document({pkg: pf.status_entry(pkg, pf.load(pkg), derive(pkg, scorecard[pkg]))
                               for pkg in scorecard})


def write_report(scorecard: dict, path: str) -> None:
    icon = {pe.PASS: '✓', pe.PARTIAL: '◐', pe.FAIL: '✗'}
    lines = ['# Package scorecard', '',
             'Generated by `tools/evaluate_packages.py --report`. Every package × track graded on six '
             'dimensions — ✓ pass, ◐ partial, ✗ fail — against the criteria in '
             '[README.md](README.md#the-scorecard). A dimension is its worst criterion; *hygiene* '
             f"criteria ({', '.join(sorted(pe.HYGIENE))}) never keep a package from `audited`.", '',
             '| Package | Track | Status | ' + ' | '.join(d.title() for d in pe.DIMENSIONS) + ' |',
             '|---|---|---|' + '---|' * len(pe.DIMENSIONS)]
    for pkg in sorted(scorecard):
        excluded = set((pf.load(pkg) or {}).get('excluded_tracks') or {})
        for tid in sorted(scorecard[pkg]):
            dims = pe.dimension_grades({c: tuple(g) for c, g in scorecard[pkg][tid].items()})
            mark = ' (excluded)' if tid in excluded else ''
            lines.append(f"| {pkg} | {tid}{mark} | {derive(pkg, scorecard[pkg])} | "
                         + ' | '.join(icon[dims[d]] for d in pe.DIMENSIONS) + ' |')
    lines += ['', '## What is not passing', '']
    for pkg in sorted(scorecard):
        lines.append(f'### {pkg}')
        lines.append('')
        shared = {c for c in scorecard[pkg][next(iter(scorecard[pkg]))]
                  if (c[0] in 'SD' and c != 'S5') or c == 'X1'}
        listed = False
        first = next(iter(sorted(scorecard[pkg])))
        for c in sorted(shared):
            g, detail = scorecard[pkg][first][c]
            if g != pe.PASS:
                lines.append(f"- {icon[g]} **{c}** {pe.CRITERIA[c]} — {detail}")
                listed = True
        for tid in sorted(scorecard[pkg]):
            for c, (g, detail) in sorted(scorecard[pkg][tid].items()):
                if c in shared or g == pe.PASS:
                    continue
                lines.append(f"- {icon[g]} **{c}** `{tid}` {pe.CRITERIA[c]} — {detail}")
                listed = True
        if not listed:
            lines.append('Every criterion passes.')
        lines.append('')
    with open(path, 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(lines))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--package', action='append')
    ap.add_argument('--report')
    ap.add_argument('--update-baseline', action='store_true')
    ap.add_argument('--accept-worse', action='store_true',
                    help='with --update-baseline: record worse grades too (a stricter grader, never a worse package)')
    ap.add_argument('--json', help='write the scorecard as JSON to this path')
    args = ap.parse_args()

    every = sorted(p['id'] for p in loader.load_philosophies())
    packages = args.package or every
    scorecard, fid_rows, orphans = run(packages)
    if args.report:
        write_report(scorecard, args.report)
        print(f'report: {args.report}')
    if args.json:
        with open(args.json, 'w') as fh:
            json.dump(scorecard, fh, indent=1)

    current = {f"{pkg}/{tid}|{c}": g[0] for pkg, tracks in scorecard.items()
               for tid, crit in tracks.items() for c, g in crit.items()}
    baseline = {}
    if os.path.exists(BASELINE):
        with open(BASELINE) as fh:
            baseline = json.load(fh)
    if args.package:
        baseline = {k: v for k, v in baseline.items() if k.split('/')[0] in packages}
    worse = sorted(k for k, g in current.items() if k in baseline and pe.RANK[g] > pe.RANK[baseline[k]])
    new = sorted(k for k in current if k not in baseline)
    better = sorted(k for k, g in current.items() if k in baseline and pe.RANK[g] < pe.RANK[baseline[k]])
    gone = sorted(k for k in baseline if k not in current)

    gated, new_fid, fixed_fid = cf.gate(fid_rows, packages if args.package else None)

    with open(coverage.BASELINE) as fh:
        known_orphans = json.load(fh)
    new_orphans = {p: sorted(set(o) - set(known_orphans.get(p, []))) for p, o in orphans.items()}
    reached_orphans = {p: sorted(set(known_orphans.get(p, [])) - set(o)) for p, o in orphans.items()}
    new_orphans = {p: o for p, o in new_orphans.items() if o}
    reached_orphans = {p: o for p, o in reached_orphans.items() if o}

    if args.update_baseline:
        if args.package:
            print('--update-baseline needs the whole run (no --package)')
            return 2
        if (worse and not args.accept_worse) or new_fid or new_orphans:
            print('Refusing to record a worse scorecard, a new fidelity finding or a new orphan:')
            for k in worse:
                print(f'  - {k}: {baseline[k]} -> {current[k]}')
            for k in new_fid:
                print(f'  - {k}')
            for p, o in new_orphans.items():
                print(f'  - {p}: orphaned {", ".join(o)}')
            if worse and not new_fid and not new_orphans:
                print('A stricter grader regrades packages it did not change: --accept-worse records it.')
            return 1
        for k in worse:
            print(f'  accepted worse: {k}: {baseline[k]} -> {current[k]}')
        with open(BASELINE, 'w') as fh:
            json.dump(dict(sorted(current.items())), fh, indent=1)
            fh.write('\n')
        cf.write_baseline(gated)
        coverage.BASELINE.write_text(json.dumps(dict(sorted(orphans.items())), indent=2, sort_keys=True) + '\n')
        with open(STATUS, 'w', encoding='utf-8') as fh:
            fh.write(status_text(scorecard))
        print(f'baselines written: {len(current)} grades, {len(gated)} fidelity findings, '
              f'{sum(len(o) for o in orphans.values())} orphans; {os.path.relpath(STATUS, ROOT)}')
        return 0

    failed = False
    if not args.package:
        with open(STATUS, encoding='utf-8') as fh:
            if fh.read() != status_text(scorecard):
                print(f'{os.path.relpath(STATUS, ROOT)} is not what the records and these grades write '
                      '(run --update-baseline)')
                failed = True
    counts = defaultdict(int)
    for g in current.values():
        counts[g] += 1
    print(f"{counts['pass']} pass, {counts['partial']} partial, {counts['fail']} fail "
          f"over {len(scorecard)} package(s); {len(gated)} fidelity findings")
    # A gain not recorded is a gain the next change may quietly lose: the
    # baseline moves in the change that earns it.
    for k in better:
        print(f'  better, not recorded: {k}: {baseline[k]} -> {current[k]}')
    for k in gone:
        print(f'  in the baseline, no longer graded: {k}')
    for k in fixed_fid:
        print(f'  fidelity finding no longer fires: {k}')
    for p, o in reached_orphans.items():
        print(f'  {p}: no longer orphaned: {", ".join(o)}')
    if better or gone or fixed_fid or reached_orphans:
        print('The baselines are stale: run --update-baseline and commit them with this change.')
    for k in worse:
        print(f'  worse: {k}: {baseline[k]} -> {current[k]}')
    for k in new:
        print(f'  new: {k} ({current[k]})')
    for k in new_fid:
        print(f'  new fidelity finding: {k}')
    for p, o in new_orphans.items():
        print(f'  {p}: newly orphaned: {", ".join(o)}')
    stale = better or gone or fixed_fid or reached_orphans
    return 1 if (failed or worse or new or new_fid or new_orphans or stale) else 0


if __name__ == '__main__':
    sys.exit(main())
