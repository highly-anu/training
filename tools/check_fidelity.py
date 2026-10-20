#!/usr/bin/env python
"""Does each philosophy's generated program do what its theory says?

Generates every philosophy x track in full (every phase, its declared weeks)
for a small matrix of athlete profiles, and runs `src/fidelity.check_program`
over each program: weekly shape against the phase framework's
`sessions_per_week`, planned intensity against `intensity_distribution`,
deloads against `deload_protocol`, archetype level and phase fit, recovery
windows, equipment and injury compliance, and the phase's own `checks:`
block in philosophy.yaml.

Profiles: the track's ideal days with everything available, its lowest and
highest accepted day counts, a kettlebell-only and a bodyweight-only home,
a 45-minute session, and two injuries. A profile whose day count a phase's
framework does not accept skips that phase's findings, because the theory
was never written for it.

Usage:
  .venv/bin/python tools/check_fidelity.py                 # gate against the baseline
  .venv/bin/python tools/check_fidelity.py --package starting_strength
  .venv/bin/python tools/check_fidelity.py --report docs/fidelity-report.md
  .venv/bin/python tools/check_fidelity.py --update-baseline

Exits 1 when an error or warning appears that tools/fidelity_baseline.json
does not list. The baseline only shrinks: fix the cause, rerun with
--update-baseline, and commit the smaller file.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from src import fidelity, goals, loader, phases, provenance  # noqa: E402
from src.generator import generate  # noqa: E402
from src.validator import validate  # noqa: E402
from tools.check_styles import ALL_EQUIPMENT  # noqa: E402

BASELINE = os.path.join(ROOT, 'tools', 'fidelity_baseline.json')
LEVEL_ORDER = ['novice', 'intermediate', 'advanced', 'elite']


def _profiles_of(name: str) -> dict:
    return {p['id']: p['equipment'] for p in loader.load_equipment_profiles()}[name]


def _track_ranges(track: dict, fw_by_id: dict) -> tuple[int, int, int, str]:
    """(ideal days, lowest, highest, level) every phase of the track accepts."""
    lo, hi = 1, 7
    levels = set(LEVEL_ORDER)
    for ph in track['phases']:
        aw = fw_by_id.get(ph['framework_id'], {}).get('applicable_when', {})
        lo = max(lo, aw.get('days_per_week_min', 1))
        hi = min(hi, aw.get('days_per_week_max', 7))
        if aw.get('training_level'):
            levels &= set(aw['training_level'])
    if lo > hi:  # phases disagree; take the first phase's range
        aw = fw_by_id.get(track['phases'][0]['framework_id'], {}).get('applicable_when', {})
        lo, hi = aw.get('days_per_week_min', 1), aw.get('days_per_week_max', 7)
    exp = fw_by_id.get(track['phases'][0]['framework_id'], {}).get('expectations', {})
    ideal = min(max(exp.get('ideal_days_per_week') or lo, lo), hi)
    level = 'intermediate' if 'intermediate' in levels else \
        next((lv for lv in LEVEL_ORDER if lv in levels), 'intermediate')
    return ideal, lo, hi, level


def profiles_for(track: dict, fw_by_id: dict) -> list[tuple[str, dict]]:
    ideal, lo, hi, level = _track_ranges(track, fw_by_id)
    exp = fw_by_id.get(track['phases'][0]['framework_id'], {}).get('expectations', {})
    minutes = exp.get('ideal_session_minutes') or 60

    def c(**kw):
        base = {'days_per_week': ideal, 'session_time_minutes': minutes,
                'training_level': level, 'equipment': list(ALL_EQUIPMENT),
                'injury_flags': [], 'fatigue_state': 'normal', 'periodization_week': 1}
        base.update(kw)
        return base

    out = [(f'ideal-{ideal}d', c())]
    for d in sorted({lo, hi} - {ideal}):
        out.append((f'{d}d', c(days_per_week=d)))
    out += [
        ('kb-home', c(equipment=_profiles_of('home_kb_only'))),
        ('bodyweight', c(equipment=_profiles_of('bodyweight_only'))),
        ('45min', c(session_time_minutes=45)),
        ('lumbar-disc', c(injury_flags=['lumbar_disc'])),
        ('shoulder', c(injury_flags=['shoulder_impingement'])),
    ]
    return out


def contract_entry(constraints: dict, contract: dict | None) -> dict:
    """A contract athlete who qualifies: two bells and the level's mastery."""
    if not contract:
        return constraints
    return {**constraints, 'kettlebell_count': constraints.get('kettlebell_count', 2),
            'mastered_exercises': sorted({eid for m in contract['modules']
                                          if constraints['training_level'] in m['training_levels']
                                          for eid in m.get('requires_mastery', [])})}


def iter_programs(package: str | None = None, extra_profiles=None):
    """One record per philosophy x track x profile: what was asked and what came back.

    Each record carries `phil`, `track`, `goal`, `policy`, `lib`, `frameworks`,
    `label`, `profile`, `constraints`, `validation` (the pre-flight result),
    `program` (None when the pre-flight refused) and `fidelity` (whether the
    fidelity rules read it). `extra_profiles(phil, track, goal, base)` may add
    `(name, constraints, {'weeks': n, 'fidelity': False})` rows: the package
    scorecard's level and constraint profiles (tools/evaluate_packages.py),
    generated in the same pass as the fidelity ones.
    """
    frameworks = loader.load_all_frameworks()
    fw_list = list(frameworks.values())
    data = loader.load_all_data()

    for phil in sorted(loader.load_philosophies(), key=lambda p: p['id']):
        if package and phil['id'] != package:
            continue
        for track in phases.tracks_of(phil):
            goal = goals.philosophy_to_goal(phil['id'], fw_list, track_id=track['id'])
            policy = provenance.resolve_source_policy(goal)
            lib = provenance.scope(data, policy)
            n_weeks = sum(int(p.get('weeks') or 1) for p in track['phases'])
            profiles = [(name, c, {'weeks': n_weeks, 'fidelity': True})
                        for name, c in profiles_for(track, frameworks)]
            contract = goal.get('training_contract')
            if contract:
                base = profiles[0][1]
                profiles += [(f'level-{level}', {**base, 'training_level': level}, {'weeks': n_weeks, 'fidelity': True})
                             for level in contract['training_levels'] if level != base['training_level']]
            if extra_profiles:
                profiles += extra_profiles(phil, track, goal, profiles[0][1])
            for profile, constraints, opts in profiles:
                constraints = contract_entry(constraints, contract)
                result = validate(goal, constraints, lib['archetypes'], lib['modalities'],
                                  lib['injury_flags'], policy=policy)
                program = None
                if result.feasible:
                    program = generate(goal_id=goal['id'], goal_dict=goal, constraints=constraints,
                                       num_weeks=opts['weeks'], output_format='dict', policy=policy)
                yield {'phil': phil, 'track': track, 'goal': goal, 'policy': policy, 'lib': lib,
                       'frameworks': frameworks, 'label': f"{phil['id']}/{track['id']}",
                       'profile': profile, 'constraints': constraints, 'validation': result,
                       'program': program, 'fidelity': opts.get('fidelity', True)}


def fidelity_rows(rec: dict) -> list[dict]:
    """The fidelity findings of one `iter_programs` record."""
    label, profile, track = rec['label'], rec['profile'], rec['track']
    result, program, frameworks = rec['validation'], rec['program'], rec['frameworks']
    if not result.feasible:
        return [{'label': label, 'profile': profile, 'finding': {
            'rule': 'infeasible', 'severity': 'info', 'phase_id': None,
            'subject': ','.join(e['code'] for e in result.errors),
            'detail': '; '.join(e.get('message', e['code']) for e in result.errors),
            'weeks': [], 'key': 'None|infeasible|' + ','.join(e['code'] for e in result.errors)}}]
    if program.get('validation_errors'):
        severity = 'error' if profile.startswith(('ideal-', 'level-')) else 'info'
        return [{'label': label, 'profile': profile, 'finding': {
            'rule': 'contract_unfulfilled', 'severity': severity, 'phase_id': None,
            'subject': track['id'], 'detail': str(program['validation_errors']),
            'weeks': [], 'key': 'None|contract_unfulfilled|' + track['id']}}]
    days = rec['constraints']['days_per_week']
    out_of_range = {
        ph['id'] for ph in track['phases']
        if not (frameworks.get(ph['framework_id'], {}).get('applicable_when', {})
                .get('days_per_week_min', 1) <= days <=
                frameworks.get(ph['framework_id'], {}).get('applicable_when', {})
                .get('days_per_week_max', 7))
    }
    return [{'label': label, 'profile': profile, 'finding': f.as_dict()}
            for f in fidelity.check_program(program, rec['phil'], track, rec['constraints'], frameworks, rec['lib'])
            if f.phase_id not in out_of_range]


def run(package: str | None = None) -> list[dict]:
    """Every finding, as dicts carrying label, profile and the finding."""
    return [row for rec in iter_programs(package) for row in fidelity_rows(rec)]


def _gate_key(row: dict) -> str:
    return f"{row['label']}|{row['profile']}|{row['finding']['key']}"


def write_report(rows: list[dict], path: str) -> None:
    by_pkg: dict[str, list] = defaultdict(list)
    for r in rows:
        by_pkg[r['label']].append(r)
    lines = ['# Fidelity report', '',
             'Generated by `tools/check_fidelity.py`. Each line is one rule on one phase; '
             'the profiles column lists the athlete profiles it fired for.', '']
    sev_rank = {'error': 0, 'warn': 1, 'info': 2}
    totals = defaultdict(int)
    for r in rows:
        totals[r['finding']['severity']] += 1
    lines.append(f"Totals: {totals['error']} errors, {totals['warn']} warnings, "
                 f"{totals['info']} info (profile x phase findings).")
    lines.append('')
    for label in sorted(by_pkg):
        lines += [f'## {label}', '']
        merged: dict[str, dict] = {}
        for r in by_pkg[label]:
            f = r['finding']
            m = merged.setdefault(f['key'], {**f, 'profiles': []})
            if r['profile'] not in m['profiles']:
                m['profiles'].append(r['profile'])
        items = sorted(merged.values(), key=lambda f: (sev_rank[f['severity']], f['phase_id'] or '', f['rule']))
        if not items:
            lines += ['No findings.', '']
            continue
        lines += ['| | Phase | Rule | Finding | Profiles |', '|---|---|---|---|---|']
        for f in items:
            icon = {'error': 'E', 'warn': 'W', 'info': 'i'}[f['severity']]
            detail = f['detail'].replace('|', '/')
            lines.append(f"| {icon} | {f['phase_id'] or '—'} | `{f['rule']}` | {detail} | "
                         f"{', '.join(f['profiles'])} |")
        lines.append('')
    with open(path, 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(lines))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--package')
    ap.add_argument('--report')
    ap.add_argument('--update-baseline', action='store_true')
    ap.add_argument('--json', help='write every finding as JSON to this path')
    args = ap.parse_args()

    rows = run(args.package)
    gated = sorted({_gate_key(r) for r in rows if r['finding']['severity'] in ('error', 'warn')})

    if args.report:
        write_report(rows, args.report)
        print(f'report: {args.report}')
    if args.json:
        with open(args.json, 'w') as fh:
            json.dump(rows, fh, indent=1)

    if args.update_baseline:
        if args.package:
            print('--update-baseline needs the whole run (no --package)')
            return 2
        if os.path.exists(BASELINE):
            with open(BASELINE) as fh:
                previous = set(json.load(fh))
            additions = sorted(set(gated) - previous)
            if additions:
                print('Refusing to grow the fidelity baseline; fix the new findings:')
                for key in additions:
                    print(f'  - {key}')
                return 1
        with open(BASELINE, 'w') as fh:
            json.dump(gated, fh, indent=1)
            fh.write('\n')
        print(f'baseline: {len(gated)} known findings written')
        return 0

    known = set()
    if os.path.exists(BASELINE):
        with open(BASELINE) as fh:
            known = set(json.load(fh))
    if args.package:
        known = {k for k in known if k.startswith(args.package + '/')}
    new = [k for k in gated if k not in known]
    fixed = sorted(known - set(gated))
    sev = defaultdict(int)
    for r in rows:
        sev[r['finding']['severity']] += 1
    print(f"{sev['error']} errors, {sev['warn']} warnings, {sev['info']} info; "
          f"{len(known)} in the baseline")
    if fixed:
        print(f'{len(fixed)} baseline finding(s) no longer fire — run --update-baseline to drop them')
    if new:
        print(f'{len(new)} new finding(s):')
        for k in new:
            print(f'  - {k}')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
