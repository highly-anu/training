"""Explore ▸ Philosophies ▸ Compare: two or three philosophies side by side.

The reference half reads each philosophy's `glance` (src/explore_philosophy.py),
the same keys for every package, and says what the set shares and what only
one of them has — so neither client compares lists itself. Likeness is
`similarity.philosophy_similarity`, the score the landing sorts by.

Pure over the loaded data and cheap (set work over two or three glances), so
it is built per request rather than cached per id list.
"""
from __future__ import annotations

import itertools

from src import similarity
from src.explore_philosophy import _loaded, glance_all, words

MIN_IDS = 2
MAX_IDS = 3

# Two intensity splits read alike when no band differs by more than this share.
_INTENSITY_TOLERANCE = 0.05


class CompareError(ValueError):
    """A request that cannot be compared: `status` is the HTTP answer."""

    def __init__(self, message: str, status: int = 422):
        super().__init__(message)
        self.status = status


def parse_ids(raw: str | None) -> list[str]:
    """`a,b[,c]` → distinct ids in the order given; raises CompareError."""
    ids: list[str] = []
    for part in (raw or '').split(','):
        part = part.strip()
        if part and part not in ids:
            ids.append(part)
    if not MIN_IDS <= len(ids) <= MAX_IDS:
        raise CompareError(f'Compare takes {MIN_IDS} to {MAX_IDS} distinct philosophies')
    return ids


def _partition(lists: dict[str, list], key=lambda x: x) -> dict:
    """What every list holds (`shared`, in the first list's order), what one
    list alone holds (`only`, per list) and, with three, what two hold
    (`some`: each item with the ids that hold it)."""
    holders: dict = {}
    for pid, items in lists.items():
        for x in items:
            ids = holders.setdefault(key(x), (x, []))[1]
            if pid not in ids:
                ids.append(pid)
    everyone = len(lists)
    return {
        'shared': [x for x, ids in holders.values() if len(ids) == everyone],
        'only': {pid: [x for x in items if len(holders[key(x)][1]) == 1] for pid, items in lists.items()},
        'some': [{'item': x, 'ids': ids} for x, ids in holders.values() if 1 < len(ids) < everyone],
    }


def _ideal(span: dict | None):
    return (span or {}).get('ideal')


def _all_same(values: list) -> bool:
    return all(v == values[0] for v in values[1:])


def _intensity_same(splits: list[dict]) -> bool:
    if not all(splits):
        return not any(splits)
    bands = set().union(*splits)
    return all(abs(a.get(b, 0) - c.get(b, 0)) <= _INTENSITY_TOLERANCE
               for a, c in itertools.combinations(splits, 2) for b in bands)


def _standards(glance: dict) -> list[dict]:
    """The standards a philosophy is measured by, each saying whether one of
    its phases tests it (the glance lists tested standards by name)."""
    tested = set(glance.get('tested') or [])
    out = [{**s, 'tested': s['name'] in tested} for s in (glance.get('measures') or {}).get('standards') or []]
    named = {s['name'] for s in out}
    out += [{'id': None, 'name': n, 'domain': None, 'tested': True} for n in tested if n not in named]
    return out


def compare(ids: list[str]) -> dict:
    """The comparison document for 2–3 philosophy ids, in the order asked.
    Raises CompareError (404) for an id no package declares."""
    by_id = {g['id']: g for g in glance_all()}
    unknown = [i for i in ids if i not in by_id]
    if unknown:
        raise CompareError(f"Unknown philosoph{'ies' if len(unknown) > 1 else 'y'}: {', '.join(unknown)}", 404)
    raw = {p['id']: p for p in _loaded()['philosophies']}
    glances = [{**by_id[i], 'models': {'intensity': words(raw[i].get('intensity_model')) or None,
                                       'progression': words(raw[i].get('progression_philosophy')) or None}}
               for i in ids]

    pairs = []
    for a, b in itertools.combinations(ids, 2):
        sim = similarity.philosophy_similarity(raw[a], raw[b])
        pairs.append({'a': a, 'b': b, **sim})

    standards = {g['id']: _standards(g) for g in glances}
    standards_split = _partition(standards, key=lambda s: s['name'])
    # A standard two hold may be tested by one and only measured by the other.
    def tested_by(s: dict) -> dict:
        return {**{k: v for k, v in s.items() if k != 'tested'},
                'testedBy': [pid for pid, items in standards.items()
                             if any(x['name'] == s['name'] and x['tested'] for x in items)]}
    standards_split['shared'] = [tested_by(s) for s in standards_split['shared']]
    standards_split['some'] = [{**e, 'item': tested_by(e['item'])} for e in standards_split['some']]

    track_weeks = max((t.get('weeks') or 0 for g in glances for t in g['tracks']), default=0)
    return {
        'ids': ids,
        'philosophies': glances,
        'scale': {'trackWeeks': track_weeks},
        'pairs': pairs,
        'same': {
            'weeks': _all_same([_ideal(g['weeks']) for g in glances]),
            'daysPerWeek': _all_same([_ideal(g['daysPerWeek']) for g in glances]),
            'sessionMinutes': _all_same([_ideal(g['sessionMinutes']) for g in glances]),
            'levels': _all_same([g['levels'] for g in glances]),
            'tracks': _all_same([len(g['tracks']) for g in glances]),
            'mix': _all_same([sorted(m['modality'] for m in g['mix']) for g in glances]),
            'intensity': _intensity_same([g['intensity'] or {} for g in glances]),
            'intensityModel': _all_same([g['models']['intensity'] for g in glances]),
            'progression': _all_same([g['models']['progression'] for g in glances]),
            'headline': _all_same([(g['measures'] or {}).get('headline') for g in glances]),
        },
        'bias': _partition({g['id']: g['bias'] for g in glances}),
        'equipment': _partition({g['id']: g['equipment'] for g in glances}, key=lambda e: e['id']),
        'standards': standards_split,
    }


# ── For you: one philosophy generated against the athlete's profile ─────────

# The longest shipped track is 29 weeks; a track runs its full length so a
# phase that cannot fit (Uphill's 106-minute muscular-endurance days) shows.
MAX_WEEKS = 30

_TEST_SKIPPED = {
    'overreached': 'you were overreached that week',
    'deload': 'it fell on a deload week',
    'archetype_unavailable': 'the test is not available',
    'level': 'it is beyond your level',
    'equipment_gap': 'it needs equipment you do not have',
    'no_session_of_modality': 'no session that week to stand in for',
    'session_too_short': 'your session is too short for it',
    'injury_skip': 'an injury rules out a movement in it',
}


def track_for(glance: dict, track_id: str | None) -> dict | None:
    """The glance's track by id, else its primary; None for an unknown id."""
    if track_id:
        return next((t for t in glance['tracks'] if t['id'] == track_id), None)
    return next((t for t in glance['tracks'] if t['id'] == glance['primaryTrackId']), glance['tracks'][0]
                if glance['tracks'] else None)


def weeks_for(track: dict) -> int:
    return max(1, min(int(track.get('weeks') or 4), MAX_WEEKS))


def _weighted(phases: list[dict], value) -> dict:
    """Σ value(phase) × weeks / Σ weeks, per key of the dicts `value` returns."""
    total = sum(p.get('weeks') or 0 for p in phases) or 1
    out: dict = {}
    for p in phases:
        for k, v in (value(p) or {}).items():
            out[k] = out.get(k, 0) + (v or 0) * (p.get('weeks') or 0) / total
    return out


def for_athlete(program: dict, glance: dict, track: dict, assumed: list[dict],
                athlete_equipment: list[str] | None) -> dict:
    """What `program` (generate's answer for this philosophy and track on the
    athlete's profile) gives the athlete, in the comparison's numbers — read
    from what generate already reports (`phase_summary`, `coverage_report`,
    `held_back`, `validation`), nothing recomputed."""
    from src.blockers import missing_equipment

    weeks = program.get('weeks') or []
    validation = program.get('validation') or {}
    equipment_names = {e['id']: e['name'] for e in glance['equipment']}
    missing = missing_equipment([e['id'] for e in glance['equipment']], athlete_equipment) \
        if athlete_equipment is not None else []
    base = {
        'id': glance['id'], 'trackId': track['id'], 'trackName': track['name'],
        'feasible': bool(weeks), 'weeks': len(weeks), 'ofWeeks': weeks_for(track), 'trackWeeks': track.get('weeks'),
        'assumed': assumed,
        'missingEquipment': [{'id': e, 'name': equipment_names.get(e, words(e))} for e in missing],
    }
    if not weeks:
        # The message only: a validator's suggested fix names engine keys
        # ("days_per_week", "goal.framework_selection").
        reasons = [{'code': e.get('code'), 'message': e.get('message')} for e in validation.get('errors') or []]
        if not reasons and program.get('detail'):
            reasons = [{'code': None, 'message': program['detail']}]
        return {**base, 'reasons': reasons}

    days = [sum(1 for ss in (w.get('schedule') or {}).values() if ss) for w in weeks]
    sessions = [sum(len(ss or []) for ss in (w.get('schedule') or {}).values()) for w in weeks]
    phases = program.get('phase_summary') or []
    minutes = _weighted(phases, lambda p: {'m': (p.get('minutes_per_week') or {}).get('mean')}).get('m')
    mix = _weighted(phases, lambda p: p.get('sessions_per_week'))
    coverage = program.get('coverage_report') or {}
    warnings = validation.get('warnings') or []
    return {
        **base,
        'reasons': [],
        'perWeek': {'days': round(sum(days) / len(days), 1), 'sessions': round(sum(sessions) / len(sessions), 1),
                    'minutes': round(minutes) if minutes is not None else None},
        # In the glance's bands (`zone1_2_pct`…), where the phase summary says `zone1_2`.
        'intensity': {(k if k.endswith('_pct') else f'{k}_pct'): round(v, 3)
                      for k, v in _weighted(phases, lambda p: p.get('intensity')).items()},
        'mix': [{'modality': m, 'perWeek': round(v, 1)} for m, v in sorted(mix.items(), key=lambda kv: -kv[1])],
        'heldBack': program.get('held_back') or {'slots': 0, 'sessions': 0},
        # Each of these is one of the package's sessions the selector passed over.
        'skippedForEquipment': len({w.get('message') for w in warnings if w.get('code') == 'EQUIPMENT_MISSING'}),
        'sessionCount': (glance.get('counts') or {}).get('sessions'),
        'gaps': {'sessions': len(coverage.get('unfilled_sessions') or []),
                 'slots': len(coverage.get('unfilled_slots') or []),
                 'substituted': [{'week': s.get('week'), 'modality': s.get('modality'),
                                  'insteadOf': s.get('substituted_for'), 'reason': s.get('reason')}
                                 for s in coverage.get('substituted_sessions') or []]},
        'tests': {'placed': len(coverage.get('placed_tests') or []),
                  'skipped': [{'week': t.get('week'),
                               'why': _TEST_SKIPPED.get(t.get('reason'), words(t.get('reason')) or 'not placed')}
                              for t in coverage.get('skipped_tests') or []]},
        'warnings': [{'code': w.get('code'), 'message': w.get('message')} for w in warnings
                     if w.get('code') != 'EQUIPMENT_MISSING'],
        'phases': [{'id': p.get('phase_id'), 'name': p.get('name'), 'kind': p.get('kind'), 'weeks': p.get('weeks'),
                    'sessions': round(sum((p.get('sessions_per_week') or {}).values()), 1),
                    'minutes': (p.get('minutes_per_week') or {}).get('mean')} for p in phases],
    }
