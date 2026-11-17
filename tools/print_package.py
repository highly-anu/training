#!/usr/bin/env python
"""A package's programs beside its rules, for the review of output against
the dossier (docs/package-fidelity/README.md, "Working a package", step 2).

For each track: the record's rules with what enforces each, whether the
source weeks reproduce, then the weeks the package generates under the
fidelity profiles (the track's ideal athlete, its lowest and highest days, a
kettlebell home, bodyweight, 45 minutes, two injuries) — refused profiles say
why. Read it against data/packages/<package>/dossier.md and list each
difference; record the review in the package's fidelity.yaml (`reviews`).

    .venv/bin/python tools/print_package.py wildman_kettlebell [--weeks 2] [--track general_practice]
        [--profile ideal] [--out /tmp/wildman.md]
"""
from __future__ import annotations

import argparse
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
os.environ.setdefault('SUPABASE_URL', '')

from src import package_fidelity as pf, source_weeks  # noqa: E402
from src.output import _fmt_week  # noqa: E402
from tools import check_fidelity as cf  # noqa: E402


def _rules(record: dict | None) -> list[str]:
    if not record or not record.get('rules'):
        return ['*No rules recorded (data/packages/<id>/fidelity.yaml).*', '']
    lines = ['| | Rule | Enforced by |', '|---|---|---|']
    for r in record['rules']:
        enforced = '<br>'.join(f'`{e}`' for e in r.get('enforced_by') or []) or '**debt**'
        lines.append(f"| {r['id']} | {r['text']} | {enforced} |")
    for i in record.get('inventions') or []:
        lines.append(f"| {i['id']} | *(invention)* {i['text']} | "
                     + '<br>'.join(f'`{e}`' for e in i.get('implemented_by') or []) + ' |')
    return lines + ['']


def _weeks_check(pkg: str) -> list[str]:
    n, structure, numbers = source_weeks.check(pkg)
    if not n:
        return ['Source weeks: none recorded.', '']
    if not structure and not numbers:
        return [f'Source weeks: all {n} reproduce.', '']
    return [f'Source weeks: {n} entries —'] + [f'- {m}' for m in structure + numbers] + ['']


def render(pkg: str, weeks: int, track: str | None, profile: str | None) -> str:
    out = [f'# {pkg}: what it generates, beside its rules', '']
    out += ['## Rules', ''] + _rules(pf.load(pkg)) + _weeks_check(pkg)
    for rec in cf.iter_programs(pkg, track_id=track, profile_prefix=profile, max_weeks=weeks):
        out += [f"## {rec['track']['id']} — {rec['profile']}", '']
        c = rec['constraints']
        out += [f"{c['days_per_week']} days, {c['session_time_minutes']} min, {c['training_level']}, "
                f"{len(c['equipment'])} pieces of equipment"
                + (f", injuries: {', '.join(c['injury_flags'])}" if c.get('injury_flags') else ''), '']
        program = rec['program']
        if not rec['validation'].feasible or not program or program.get('validation_errors'):
            why = [e.get('message', e.get('code')) for e in rec['validation'].errors] or \
                  (program or {}).get('validation_errors') or ['no weeks']
            out += ['**Refused:** ' + '; '.join(map(str, why)), '']
            continue
        for w in program['weeks'][:weeks]:
            out += [_fmt_week(w).replace('## Week', '### Week').replace('\n### ', '\n#### '), '']
        for msg in program.get('compromises') or []:
            out.append(f'- *{msg}*')
        out.append('')
    return '\n'.join(out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('package')
    ap.add_argument('--weeks', type=int, default=2)
    ap.add_argument('--track')
    ap.add_argument('--profile', help='a profile name prefix: ideal, 3d, kb-home, bodyweight, 45min …')
    ap.add_argument('--out')
    args = ap.parse_args()
    text = render(args.package, args.weeks, args.track, args.profile)
    if args.out:
        with open(args.out, 'w', encoding='utf-8') as fh:
            fh.write(text)
        print(f'written: {args.out}')
    else:
        print(text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
