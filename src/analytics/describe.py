"""A package's analytics spec, described for a reader rather than run.

The Program tab shows the *results* of a spec against the active program;
the Explore tab shows the spec itself — what a methodology counts as progress,
over which sessions, against what, and what has to be logged for it to be
measurable. This module turns `spec.spec_for()` into that: ids resolved to
names, `expected` normalised to a `{kind, ...}` record, and the capture
requirements unioned from the vocabulary. It is static data, so the route
serves every package at once.
"""
from __future__ import annotations

import os

from src import loader
from src.analytics import benchmarks_data, spec, vocabulary

_PACKAGES_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))),
                             'data', 'packages')


def describe_all() -> dict:
    frameworks = loader.load_all_frameworks()
    modalities = loader.load_all_modalities()
    archetypes = {a['id']: a for a in loader.load_all_archetypes()}
    exercises, _ = loader.load_all_exercises()
    benchmarks = benchmarks_data.by_id()
    names = _Names(frameworks, modalities, archetypes, exercises, benchmarks)

    out = {}
    for phil in loader.load_philosophies():
        pid = phil['id']
        s = spec.spec_for(pid, frameworks=frameworks, modalities=modalities, philosophy=phil)
        out[pid] = describe(s, phil, names)
    return {'vocabulary': vocabulary.to_client(), 'philosophies': out}


def describe(s: spec.Spec, phil: dict, names: '_Names') -> dict:
    pid = s.philosophy
    entries = [_entry(e, names) for e in s.entries]
    headline = next((e['id'] for e in entries if e['headline']), None)
    file = os.path.join('data', 'packages', pid, 'analytics.yaml')
    return {
        'philosophy': pid,
        'name': phil.get('name', pid),
        'source': s.source,
        'file': file if os.path.exists(os.path.join(_PACKAGES_DIR, pid, 'analytics.yaml')) else None,
        'progressionPhilosophy': phil.get('progression_philosophy'),
        'headlineId': headline,
        'progress': entries,
        'movement': {
            'balance': list(s.balance) if s.balance_declared else list(spec.DEFAULT_BALANCE),
            'declared': s.balance_declared,
        },
        'benchmarks': _benchmarks(s, names),
        'needs': _needs(s.entries),
    }


def _entry(e: spec.Entry, names: '_Names') -> dict:
    scope = e.scope or {}
    return {
        'id': e.id,
        'label': e.label or e.id,
        'primitive': e.primitive,
        'headline': bool(e.headline),
        'source': e.source,
        'scope': {
            'modalities': names.modalities(scope.get('modalities')),
            'archetypes': names.archetypes(scope.get('archetypes')),
            'frameworks': names.frameworks(scope.get('frameworks')),
            'exercises': names.exercises(scope.get('exercises')),
            'movementPatterns': list(scope.get('movement_patterns') or []),
            'slotTypes': list(scope.get('slot_types') or []),
            'slotRoles': list(scope.get('slot_roles') or []),
            'excludeSlotRoles': list(scope.get('exclude_slot_roles') or []),
        },
        'expected': _expected(e.expected),
        'stall': ({'sessions': int(e.stall.get('sessions', 3)),
                   'tolerancePct': float(e.stall.get('tolerance_pct', 1))}
                  if isinstance(e.stall, dict) else None),
        'benchmarks': names.benchmarks(e.benchmarks),
        'targetLevel': e.target_level,
        'rpmTarget': e.rpm_target,
        'minSessions': e.min_sessions,
        'notes': e.notes or None,
    }


def _expected(expected) -> dict:
    """Normalise the spec's `expected` shorthand to {kind, field?, value?, unit?}."""
    if isinstance(expected, dict):
        if 'load_field' in expected:
            return {'kind': 'load_field', 'field': expected['load_field']}
        if 'framework_field' in expected:
            return {'kind': 'framework_field', 'field': expected['framework_field']}
        if 'constant' in expected:
            out = {'kind': 'constant', 'value': expected['constant']}
            if expected.get('unit'):
                out['unit'] = expected['unit']
            return out
        return {'kind': 'none'}
    if expected in ('prescribed', 'achieved_plus_increment'):
        return {'kind': expected}
    return {'kind': 'none'}


def _benchmarks(s: spec.Spec, names: '_Names') -> list[dict]:
    """Standards a philosophy is measured by, with why each one is here.

    `declared` (top-level `benchmarks:`) beats `entry` (a benchmark_level
    entry) beats `source` (the standard's own `sources` cites the philosophy —
    the same rule src/analytics/benchmarks.py applies to a program).
    """
    why: dict[str, str] = {}
    for b in names.benchmarks_raw.values():
        if s.philosophy in (b.get('sources') or []):
            why[b['id']] = 'source'
    for e in s.entries:
        for bid in e.benchmarks or []:
            why[bid] = 'entry'
    for bid in s.benchmarks or []:
        why[bid] = 'declared'
    out = []
    for bid, reason in why.items():
        b = names.benchmarks_raw.get(bid)
        if not b:
            continue
        out.append({'id': bid, 'name': b['name'], 'category': b['category'],
                    'domain': b.get('domain'), 'unit': b.get('unit', ''), 'why': reason})
    order = {'declared': 0, 'entry': 1, 'source': 2}
    out.sort(key=lambda b: (order[b['why']], b['name']))
    return out


def _needs(entries: list) -> list[dict]:
    """The union of what the entries need logged, each field once."""
    by_field: dict[str, list[str]] = {}
    for e in entries:
        for field in vocabulary.PRIMITIVES.get(e.primitive, {}).get('needs', []):
            by_field.setdefault(field, [])
            if e.id not in by_field[field]:
                by_field[field].append(e.id)
    return [{'field': field, **vocabulary.NEEDS[field], 'entries': ids}
            for field, ids in by_field.items() if field in vocabulary.NEEDS]


class _Names:
    """Id → {id, name} resolution; an unknown id keeps its id as its name."""

    def __init__(self, frameworks: dict, modalities: dict, archetypes: dict,
                 exercises: dict, benchmarks: dict):
        self._fw, self._mod, self._arch, self._ex = frameworks, modalities, archetypes, exercises
        self.benchmarks_raw = benchmarks

    @staticmethod
    def _resolve(ids, table: dict) -> list[dict]:
        return [{'id': i, 'name': (table.get(i) or {}).get('name') or i} for i in (ids or [])]

    def frameworks(self, ids): return self._resolve(ids, self._fw)
    def modalities(self, ids): return self._resolve(ids, self._mod)
    def archetypes(self, ids): return self._resolve(ids, self._arch)
    def exercises(self, ids): return self._resolve(ids, self._ex)

    def benchmarks(self, ids) -> list[dict]:
        out = []
        for i in ids or []:
            b = self.benchmarks_raw.get(i)
            out.append({'id': i, 'name': b['name'] if b else i,
                        'unit': b.get('unit', '') if b else '',
                        'category': b['category'] if b else None})
        return out
