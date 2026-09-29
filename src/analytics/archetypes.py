"""Per session shape: how each archetype in the block is going.

Scheduled and completed counts, the mean duration delta against the
prescription, the heart-rate profile of its matched workouts, and — for
set-based shapes — the estimated 1RM trend of its lead lift.
"""
from __future__ import annotations

from collections import defaultdict

from src.analytics.context import Context
from src.analytics.primitives.load import best_completed_set


def build(ctx: Context) -> list[dict]:
    rows: dict[str, dict] = {}
    for hit in ctx.sessions(elapsed_only=True):
        session = hit['session']
        arch = session.get('archetype') or {}
        aid = arch.get('id') or session.get('modality') or 'unknown'
        row = rows.setdefault(aid, {
            'archetypeId': aid, 'name': arch.get('name') or aid, 'category': arch.get('category'),
            'modality': session.get('modality'), 'scheduled': 0, 'completed': 0, 'matched': 0,
            'prescribedMinutes': float(arch.get('duration_estimate_minutes') or 0),
            '_deltas': [], '_hr': [], '_e1rm': defaultdict(list),
            'slotTypes': sorted({ea.get('slot_type') for ea in (session.get('exercises') or [])
                                 if ea.get('slot_type')}),
        })
        row['scheduled'] += 1
        w = ctx.workout_for(hit)
        done = ctx.completed(hit) or w is not None
        if not done:
            continue
        row['completed'] += 1
        minutes, source = ctx.duration_minutes(hit)
        if source in ('workout', 'timeline', 'logged') and row['prescribedMinutes']:
            row['_deltas'].append(100.0 * (minutes - row['prescribedMinutes']) / row['prescribedMinutes'])
        if w:
            row['matched'] += 1
            hr = w.get('heartRate') or {}
            if hr.get('avg'):
                row['_hr'].append((float(hr['avg']), float(hr.get('max') or 0)))
        logged = (ctx.log_for(hit) or {}).get('exercises') or {}
        for ea in session.get('exercises') or []:
            ex = ea.get('exercise') or {}
            if not ex.get('id') or ea.get('meta'):
                continue
            best = best_completed_set(logged.get(ex['id']))
            if best and best.get('est1rm'):
                row['_e1rm'][ex['id']].append(best['est1rm'])

    out = []
    for row in rows.values():
        deltas, hrs, e1 = row.pop('_deltas'), row.pop('_hr'), row.pop('_e1rm')
        row['completionPct'] = round(100.0 * row['completed'] / row['scheduled'], 1) if row['scheduled'] else None
        row['meanDurationDeltaPct'] = round(sum(deltas) / len(deltas), 1) if deltas else None
        row['hr'] = ({'avg': round(sum(a for a, _ in hrs) / len(hrs)),
                      'max': round(max(m for _, m in hrs))} if hrs else None)
        lead = max(e1.items(), key=lambda kv: len(kv[1]), default=None)
        row['leadLift'] = ({'exerciseId': lead[0], 'firstEst1rm': lead[1][0], 'latestEst1rm': lead[1][-1],
                            'sessions': len(lead[1])} if lead else None)
        out.append(row)
    out.sort(key=lambda r: -r['scheduled'])
    return out
