"""The athlete's results on the standards, read the same way by every screen.

A result is one dated value on a standard (`performance_logs`). The level, the
next level and the text a value prints as are worked out here, once: the web
and the phone each used to compute the level from the thresholds themselves,
and disagreed — the phone had no "below entry" and printed 1.25×BW as "1.3".

Current is the latest result (a retest after a layoff is honest even when it
is worse); best is the best result ever. Pure: no Flask, no DB.
"""
from __future__ import annotations

from datetime import date

from src.analytics import benchmarks_data as bd


def _day(raw) -> str | None:
    try:
        return date.fromisoformat(str(raw)[:10]).isoformat()
    except (TypeError, ValueError):
        return None


def point(b: dict, value: float, day: str | None, sex: str) -> dict:
    """One value placed on a standard's ladder, with its words."""
    lv = bd.level_of(b, value, sex)
    nxt = lv['next']
    return {
        'value': value, 'valueText': bd.format_value(b, value), 'date': day,
        'level': lv['level'], 'levelIndex': lv['index'],
        'next': nxt, 'nextText': bd.format_value(b, bd.thresholds(b, sex).get(nxt)) if nxt else None,
        'gap': lv['gap'], 'gapText': bd.format_value(b, lv['gap']) if lv['gap'] is not None else None,
    }


def _entries(raw: list | None) -> list[dict]:
    out = []
    for e in raw or []:
        v = e.get('value')
        if isinstance(v, bool) or not isinstance(v, (int, float)):
            continue
        out.append({'id': e.get('id'), 'value': float(v), 'date': _day(e.get('date'))})
    return out


def summarise(benchmarks, logs: dict, sex: str = 'male') -> dict:
    """{standards: {id: {current, best, count, entries}}, bodyweight}.

    `logs` is health_store.get_performance_logs' shape, oldest first. Only
    standards with at least one result appear; ids no standard has any more
    are left out rather than guessed at.
    """
    sex = sex if sex in ('male', 'female') else 'male'
    out: dict[str, dict] = {}
    for b in benchmarks:
        entries = _entries(logs.get(b['id']))
        if not entries:
            continue
        better = min if b['lower_is_better'] else max
        best = better(entries, key=lambda e: e['value'])
        latest = entries[-1]
        out[b['id']] = {
            'current': point(b, latest['value'], latest['date'], sex),
            'best': point(b, best['value'], best['date'], sex),
            'count': len(entries),
            'entries': [{**e, **{k: v for k, v in point(b, e['value'], e['date'], sex).items()
                                 if k in ('valueText', 'level', 'levelIndex')}}
                        for e in entries],
        }
    bw = _entries(logs.get(bd.BODYWEIGHT_ID))
    return {
        'sex': sex,
        'standards': out,
        'bodyweight': ({'value': bw[-1]['value'], 'valueText': bd.format_value(None, bw[-1]['value']),
                        'date': bw[-1]['date']} if bw else None),
    }


def digest_key(logs: dict) -> list:
    """What a cached analytics document must key on: every value and date, not
    the number of entries (an edit keeps the count and changes the answer)."""
    return sorted((k, e.get('id'), e.get('value'), str(e.get('date'))) for k, v in logs.items() for e in v or [])
