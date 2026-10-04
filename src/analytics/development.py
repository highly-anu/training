"""Development across programs — the one document that spans the history.

Every other analytics surface is scoped to the program in hand: the scorecard
windows its inputs to the current program's span, the progression review
reads the current program's weeks, Home's development card is the current
program against its matches. The history tables (`program_versions`,
`program_activations`, `planned_sessions`, logs and matches carrying
`session_uid`) exist so that "how have I developed across programs" can be
answered, and nothing asked them until this module.

Pure over its inputs: the route gathers, this computes, a test feeds it a
throwaway history. Shapes:

    blocks      — the activation timeline, oldest first, with completion
    lifts       — per exercise, best completed sets across the span with
                  per-block first / last / best est-1RM and a trend
    currencies  — the same for rounds, minutes and kilometres
    load        — weekly TRIMP and the PMC, each week and day with its block
    benchmarks  — each standard's PR history with the level reached per date
"""
from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from typing import Callable

from src.analytics import trend as _trend
from src.analytics import benchmarks_data as _bd
from src.analytics.primitives.load import best_completed_set

MIN_LIFT_POINTS = 2          # two points make a line and a delta; fewer is a single session
MIN_CURRENCY_POINTS = 2


@dataclass
class DevelopmentInputs:
    today: date
    window_from: date
    window_to: date
    activations: list = field(default_factory=list)          # program_history.list_activations (newest first)
    planned: dict = field(default_factory=dict)              # version id -> planned_sessions rows
    logs_by_uid: dict = field(default_factory=dict)          # health_store.get_session_logs_by_uid
    matches: list = field(default_factory=list)              # health_store.get_matches
    workouts: list = field(default_factory=list)             # summary rows
    pmc: list = field(default_factory=list)                  # [{date, ctl, atl, tsb, trimp}] over the window
    trimp_of: Callable[[dict], float] = lambda w: 0.0
    performance_logs: dict = field(default_factory=dict)     # benchmark id -> [{value, date}]
    benchmarks: list = field(default_factory=list)           # benchmarks_data.load_benchmarks()
    sex: str = 'male'
    exercise_names: dict = field(default_factory=dict)
    philosophy_names: dict = field(default_factory=dict)


# ── helpers ──────────────────────────────────────────────────────────────────

def _as_date(value) -> date | None:
    if value is None or value == '':
        return None
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    s = str(value)
    try:
        return date.fromisoformat(s[:10])
    except ValueError:
        return None


def _version_of(uid: str) -> str:
    return uid.split(':', 1)[0] if uid else ''


class _Timeline:
    """Which block was in force on a day, by activation interval."""

    def __init__(self, blocks: list[dict], today: date):
        self._spans = []
        for b in blocks:
            start = _as_date(b['from'])
            end = _as_date(b['to']) or today
            if start:
                self._spans.append((start, end, b['id'], b['versionId']))

    def block_on(self, day: date | None, version_id: str | None = None) -> int | None:
        if day is None:
            return None
        hits = [s for s in self._spans if s[0] <= day <= s[1]]
        if version_id:
            same = [s for s in hits if s[3] == version_id]
            if same:
                return same[0][2]
            # a log inside a version that is not the one in force that day
            # (a re-activation, or the day before the switch) still belongs to
            # its own version's latest block
            own = [s for s in self._spans if s[3] == version_id]
            if own:
                return own[-1][2]
        return hits[0][2] if hits else None


# ── blocks ───────────────────────────────────────────────────────────────────

def _blocks(inputs: DevelopmentInputs) -> list[dict]:
    matched_uids = {m.get('sessionUid') for m in inputs.matches
                    if m.get('sessionUid') and m.get('matchConfidence') != 'rejected'}
    out = []
    for a in sorted(inputs.activations, key=lambda a: (str(a.get('effectiveFrom')), a.get('activationId') or 0)):
        vid = a['versionId']
        start = _as_date(a.get('effectiveFrom'))
        # program_activations.effective_to is exclusive (the successor's
        # effective_from); the block's own last day is the day before.
        end_excl = _as_date(a.get('effectiveTo'))
        end = (end_excl - timedelta(days=1)) if end_excl else inputs.today
        if start is None or end < inputs.window_from or start > inputs.window_to:
            continue
        rows = inputs.planned.get(vid) or []
        in_force = [r for r in rows if (d := _as_date(r.get('date'))) and start <= d <= end]
        done = 0
        for r in in_force:
            uid = r.get('session_uid')
            log = inputs.logs_by_uid.get(uid) if uid else None
            if (log and log.get('completedAt')) or uid in matched_uids:
                done += 1
        ids = [i for i in (a.get('sourceGoalIds') or []) if i != '_blended']
        out.append({
            'id': a.get('activationId'),
            'versionId': vid,
            'label': a.get('label') or a.get('goalName') or 'Program',
            'methodologies': [{'id': i, 'name': inputs.philosophy_names.get(i, i.replace('_', ' ').title())}
                              for i in ids],
            'from': start.isoformat(),
            'to': end.isoformat() if end_excl else None,
            'isActive': bool(a.get('isActive')),
            'weeks': a.get('weekCount') or 0,
            'plannedTotal': len(rows),
            'planned': len(in_force),
            'completed': done,
            'completionPct': round(100.0 * done / len(in_force)) if in_force else None,
            'source': a.get('source'),
        })
    return out


# ── lifts and currencies ─────────────────────────────────────────────────────

def _log_date(log: dict, planned_row: dict | None) -> date | None:
    return _as_date((planned_row or {}).get('date')) or _as_date(log.get('completedAt'))


def _series(inputs: DevelopmentInputs, timeline: _Timeline):
    """One pass over the logs: per exercise, the best set and the currencies."""
    planned_by_uid = {r['session_uid']: r for rows in inputs.planned.values() for r in rows}
    lifts: dict[str, list[dict]] = defaultdict(list)
    currencies: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for uid, log in inputs.logs_by_uid.items():
        planned_row = planned_by_uid.get(uid)
        day = _log_date(log, planned_row)
        if day is None or day < inputs.window_from or day > inputs.window_to:
            continue
        block = timeline.block_on(day, _version_of(uid))
        is_deload = bool((planned_row or {}).get('is_deload'))
        for ex_id, perf in (log.get('exercises') or {}).items():
            if not isinstance(perf, dict):
                continue
            best = best_completed_set(perf)
            if best:
                lifts[ex_id].append({
                    'date': day.isoformat(), 'blockId': block, 'weight': best['weight'],
                    'reps': best['reps'], 'est1rm': best['est1rm'], 'isDeload': is_deload,
                })
            for key, metric, scale in (('rounds', 'rounds', 1.0), ('durationSec', 'minutes', 1 / 60.0),
                                       ('distanceKm', 'km', 1.0)):
                raw = perf.get(key)
                if isinstance(raw, (int, float)) and raw > 0:
                    currencies[(ex_id, metric)].append({
                        'date': day.isoformat(), 'blockId': block,
                        'value': round(float(raw) * scale, 1), 'isDeload': is_deload,
                    })
    return lifts, currencies


def _value_of(point: dict) -> float | None:
    return point.get('est1rm') or point.get('weight')


def _per_block(points: list[dict], blocks: list[dict], value) -> list[dict]:
    out = []
    for b in blocks:
        own = [p for p in points if p.get('blockId') == b['id']]
        vals = [v for p in own if (v := value(p)) is not None]
        if not vals:
            continue
        out.append({
            'blockId': b['id'], 'sessions': len(own),
            'first': vals[0], 'last': vals[-1], 'best': max(vals),
            'delta': round(vals[-1] - vals[0], 1),
        })
    return out


def _trend_of(points: list[dict], value) -> dict:
    fitted = _trend.fit([_trend.Point(x=i, value=value(p), is_deload=bool(p.get('isDeload')))
                         for i, p in enumerate(points) if value(p) is not None])
    return {'direction': fitted.direction, 'slopePct': round(fitted.slope_pct, 2), 'pointsUsed': fitted.points_used}


def _lifts(inputs: DevelopmentInputs, lifts: dict, blocks: list[dict]) -> list[dict]:
    out = []
    for ex_id, points in lifts.items():
        points.sort(key=lambda p: p['date'])
        block_ids = {p['blockId'] for p in points if p['blockId'] is not None}
        if len(points) < MIN_LIFT_POINTS and len(block_ids) < 2:
            continue
        out.append({
            'exerciseId': ex_id,
            'name': inputs.exercise_names.get(ex_id, ex_id.replace('_', ' ').title()),
            'unit': 'kg',
            'points': points,
            'perBlock': _per_block(points, blocks, _value_of),
            'trend': _trend_of(points, _value_of),
            'blocks': len(block_ids),
        })
    # the lifts seen in most blocks first, then the most points
    out.sort(key=lambda l: (-l['blocks'], -len(l['points']), l['name']))
    return out


def _currencies(inputs: DevelopmentInputs, currencies: dict, blocks: list[dict]) -> list[dict]:
    out = []
    for (ex_id, metric), points in currencies.items():
        points.sort(key=lambda p: p['date'])
        if len(points) < MIN_CURRENCY_POINTS:
            continue
        value = lambda p: p.get('value')  # noqa: E731
        out.append({
            'exerciseId': ex_id,
            'name': inputs.exercise_names.get(ex_id, ex_id.replace('_', ' ').title()),
            'metric': metric,
            'points': points,
            'perBlock': _per_block(points, blocks, value),
            'trend': _trend_of(points, value),
        })
    out.sort(key=lambda c: (-len(c['points']), c['name']))
    return out


# ── load ─────────────────────────────────────────────────────────────────────

def _load(inputs: DevelopmentInputs, timeline: _Timeline) -> dict:
    weeks: dict[str, dict] = {}
    for w in inputs.workouts:
        day = _as_date(w.get('date'))
        if day is None or day < inputs.window_from or day > inputs.window_to:
            continue
        iso = day.isocalendar()
        key = f'{iso[0]}-W{iso[1]:02d}'
        entry = weeks.setdefault(key, {'week': key, 'trimp': 0.0, 'sessions': 0,
                                       'blockId': timeline.block_on(day - timedelta(days=day.weekday() - 3))})
        entry['trimp'] += float(inputs.trimp_of(w) or 0.0)
        entry['sessions'] += 1
    weekly = [{'week': k, 'trimp': round(v['trimp']), 'sessions': v['sessions'], 'blockId': v['blockId']}
              for k, v in sorted(weeks.items())]
    pmc = []
    for p in inputs.pmc:
        day = _as_date(p.get('date'))
        if day is None or day < inputs.window_from or day > inputs.window_to:
            continue
        pmc.append({**p, 'blockId': timeline.block_on(day)})
    return {'weekly': weekly, 'pmc': pmc}


# ── benchmarks ───────────────────────────────────────────────────────────────

def _benchmarks(inputs: DevelopmentInputs) -> list[dict]:
    by_id = {b['id']: b for b in inputs.benchmarks}
    out = []
    for bid, entries in inputs.performance_logs.items():
        b = by_id.get(bid)
        if not b:
            continue
        history = []
        for e in sorted(entries, key=lambda e: str(e.get('date'))):
            day = _as_date(e.get('date'))
            value = e.get('value')
            if day is None or value is None or day < inputs.window_from or day > inputs.window_to:
                continue
            lv = _bd.level_of(b, float(value), inputs.sex)
            history.append({'date': day.isoformat(), 'value': value, 'level': lv['level'], 'levelIndex': lv['index']})
        if not history:
            continue
        out.append({
            'benchmarkId': bid, 'name': b.get('name', bid), 'unit': b.get('unit', ''),
            'lowerIsBetter': bool(b.get('lower_is_better')),
            'history': history,
            'latestLevel': history[-1]['level'], 'latestLevelIndex': history[-1]['levelIndex'],
            'levelsGained': history[-1]['levelIndex'] - history[0]['levelIndex'],
        })
    out.sort(key=lambda r: (-r['levelsGained'], -len(r['history']), r['name']))
    return out


# ── the document ─────────────────────────────────────────────────────────────

def compute_development(inputs: DevelopmentInputs) -> dict:
    blocks = _blocks(inputs)
    timeline = _Timeline(blocks, inputs.today)
    lifts_raw, currencies_raw = _series(inputs, timeline)
    return {
        'status': 'ok' if inputs.activations else 'no_history',
        'window': {'from': inputs.window_from.isoformat(), 'to': inputs.window_to.isoformat()},
        'blocks': blocks,
        'lifts': _lifts(inputs, lifts_raw, blocks),
        'currencies': _currencies(inputs, currencies_raw, blocks),
        'load': _load(inputs, timeline),
        'benchmarks': _benchmarks(inputs),
    }
