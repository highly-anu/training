"""How a program's sessions and exercises change from one phase to the next.

Program ▸ Overview on both clients lays this out; nothing in it is computed
in a browser or on the phone. It reads the stored weeks (day-name keys, slots
stripped by `api._clean_exercise_assignment`), so it works on any saved
program, including one an older iOS build re-encoded.

Per phase, in program order:

- the weekly shape (sessions per modality, averaged over working weeks),
- planned minutes per week (first, last, mean) and the intensity split,
  both from `src/fidelity.py` so the check and the display count alike,
- every archetype and exercise with how often it appears (`sessions` in the
  phase, `per_week` over its working weeks), marked `new` or `continued`
  against the previous phase, plus what the phase `dropped`,
- the loaded lifts with their first and last prescribed weight,
- `changes`: a few plain lines naming what is different from the previous
  phase.

Deload weeks are left out of the shape, minutes and intensity (a deload is not
what a phase is for) but their sessions still count as appearances.
"""
from __future__ import annotations

from collections import Counter, defaultdict

from src import fidelity


def _label(mod: str) -> str:
    return mod.replace('_', ' ').capitalize()


def _hours(minutes: float) -> str:
    return f"{minutes / 60:.1f} h" if minutes >= 90 else f"{round(minutes)} min"


def _times(n: float) -> str:
    return f"{n:g}×/week" if n == int(n) else f"{n:.1f}×/week"


def _group(weeks: list) -> list[tuple[str, list]]:
    groups: list[tuple[str, list]] = []
    for w in weeks:
        pid = w.get('phase_id') or w.get('phase')
        if groups and groups[-1][0] == pid:
            groups[-1][1].append(w)
        else:
            groups.append((pid, [w]))
    return groups


def _phase_entry(goal: dict | None, phase_id: str) -> dict:
    for e in (goal or {}).get('phase_sequence') or []:
        if e.get('phase_id') == phase_id:
            return e
    return {}


def _summarise(phase_id: str, pweeks: list, goal: dict | None) -> dict:
    entry = _phase_entry(goal, phase_id)
    work = [w for w in pweeks if not w.get('is_deload')] or pweeks
    first = pweeks[0]

    shape: Counter = Counter()
    for w in work:
        for _, s in fidelity._sessions(w):
            shape[s.get('modality')] += 1
    spw = {m: round(n / len(work), 1) for m, n in shape.most_common()}

    minutes = [fidelity.week_minutes(w) for w in work]
    buckets = dict.fromkeys(fidelity.BUCKETS, 0.0)
    for w in work:
        for _, s in fidelity._sessions(w):
            for b, m in fidelity.session_buckets(s).items():
                buckets[b] += m
    total = sum(buckets.values())
    intensity = {b.replace('_pct', ''): round(m / total, 3) for b, m in buckets.items()} if total else {}

    archetypes: dict[str, dict] = {}
    exercises: dict[str, dict] = {}
    lifts: dict[str, dict] = {}
    # Appearances in working weeks, for `per_week`; deloads still count
    # towards `sessions` (the item is in the phase) but not towards the rate,
    # so the rate agrees with `sessions_per_week`.
    work_ids = {id(w) for w in work}
    in_work: Counter = Counter()
    for w in pweeks:
        for _, s in fidelity._sessions(w):
            arch = s.get('archetype') or {}
            if arch.get('id'):
                a = archetypes.setdefault(arch['id'], {
                    'id': arch['id'], 'name': arch.get('name') or arch['id'],
                    'modality': s.get('modality'), 'sessions': 0})
                a['sessions'] += 1
                if id(w) in work_ids:
                    in_work[('a', arch['id'])] += 1
            for ea in s.get('exercises') or []:
                ex = ea.get('exercise') or {}
                if ea.get('meta') or not ex.get('id'):
                    continue
                e = exercises.setdefault(ex['id'], {
                    'id': ex['id'], 'name': ex.get('name') or ex['id'],
                    'modality': s.get('modality'), 'sessions': 0})
                e['sessions'] += 1
                if id(w) in work_ids:
                    in_work[('e', ex['id'])] += 1
                kg = (ea.get('load') or {}).get('weight_kg')
                if isinstance(kg, (int, float)) and not w.get('is_deload'):
                    lift = lifts.setdefault(ex['id'], {'id': ex['id'], 'name': e['name'],
                                                       'first_kg': kg, 'last_kg': kg})
                    lift['last_kg'] = kg

    for a in archetypes.values():
        a['per_week'] = round(in_work[('a', a['id'])] / len(work), 1)
    for e in exercises.values():
        e['per_week'] = round(in_work[('e', e['id'])] / len(work), 1)

    return {
        'phase_id': phase_id,
        'name': first.get('phase_name') or entry.get('name') or str(phase_id).replace('_', ' ').capitalize(),
        'kind': first.get('phase'),
        'framework_id': first.get('framework') or entry.get('framework_id'),
        'week_start': first.get('week_number'),
        'week_end': pweeks[-1].get('week_number'),
        'weeks': len(pweeks),
        'deload_weeks': sum(1 for w in pweeks if w.get('is_deload')),
        'sessions_per_week': spw,
        'minutes_per_week': {
            'first': round(minutes[0]) if minutes else 0,
            'last': round(minutes[-1]) if minutes else 0,
            'mean': round(sum(minutes) / len(minutes)) if minutes else 0,
        },
        'intensity': intensity,
        'archetypes': sorted(archetypes.values(), key=lambda a: (-a['sessions'], a['name'])),
        'exercises': sorted(exercises.values(), key=lambda e: (-e['sessions'], e['name'])),
        'lifts': sorted(lifts.values(), key=lambda lf: -lf['last_kg']),
    }


def _diff(cur: dict, prev: dict | None) -> None:
    """Mark statuses on `cur` against `prev` and write its `changes`."""
    if prev is None:
        for item in cur['archetypes'] + cur['exercises']:
            item['status'] = None
        cur['dropped'] = {'archetypes': [], 'exercises': []}
        cur['changes'] = []
        return

    for key in ('archetypes', 'exercises'):
        before = {i['id'] for i in prev[key]}
        for item in cur[key]:
            item['status'] = 'continued' if item['id'] in before else 'new'
    now_a = {a['id'] for a in cur['archetypes']}
    now_e = {e['id'] for e in cur['exercises']}
    cur['dropped'] = {
        'archetypes': [{k: a[k] for k in ('id', 'name', 'modality')}
                       for a in prev['archetypes'] if a['id'] not in now_a],
        'exercises': [{k: e[k] for k in ('id', 'name', 'modality')}
                      for e in prev['exercises'] if e['id'] not in now_e],
    }

    changes: list[str] = []
    a, b = prev['sessions_per_week'], cur['sessions_per_week']
    for mod in list(b) + [m for m in a if m not in b]:
        was, now = a.get(mod, 0), b.get(mod, 0)
        if not was and now:
            changes.append(f"{_label(mod)} enters, {_times(now)}")
        elif was and not now:
            changes.append(f"{_label(mod)} leaves")
        elif abs(now - was) >= 0.5:
            changes.append(f"{_label(mod)} {_times(was).split('×')[0]} → {_times(now)}")

    m0, m1 = prev['minutes_per_week']['mean'], cur['minutes_per_week']['mean']
    if m0 and abs(m1 - m0) / m0 >= 0.10:
        changes.append(f"Weekly volume {_hours(m0)} → {_hours(m1)} ({(m1 - m0) / m0:+.0%})")

    hard0 = (prev['intensity'].get('zone4_5') or 0) + (prev['intensity'].get('zone3') or 0)
    hard1 = (cur['intensity'].get('zone4_5') or 0) + (cur['intensity'].get('zone3') or 0)
    if abs(hard1 - hard0) >= 0.05:
        changes.append(f"Zone 3+ minutes {hard0:.0%} → {hard1:.0%}")

    new = [x['name'] for x in cur['archetypes'] if x['status'] == 'new']
    if new:
        changes.append('New sessions: ' + ', '.join(new[:3]) + (f' (+{len(new) - 3})' if len(new) > 3 else ''))
    gone = [x['name'] for x in cur['dropped']['archetypes']]
    if gone:
        changes.append('Gone: ' + ', '.join(gone[:3]) + (f' (+{len(gone) - 3})' if len(gone) > 3 else ''))
    cur['changes'] = changes


def build(weeks: list, goal: dict | None = None) -> list[dict]:
    """One entry per phase, in program order. A phase that recurs later (a
    repeatable block run again) gets its own entry for each run."""
    out: list[dict] = []
    for phase_id, pweeks in _group(weeks or []):
        cur = _summarise(phase_id, pweeks, goal)
        _diff(cur, out[-1] if out else None)
        out.append(cur)
    return out
