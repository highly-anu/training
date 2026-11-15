"""What a package shows before a session: the resolved briefing spec.

A package may declare it (`data/packages/<id>/briefing.yaml`, schema in
docs/schemas/briefing.schema.json): entries, tried in order, each saying for
the exercises in its scope what an earlier occurrence of the same thing is
(`same_as`), which numbers lead (`show`), how much history is listed and which
suggestions apply. The default entries follow a package's own, so whatever a
package leaves out — and every package without the file — is read by how its
loads were written: a contract module by its progression model, a named
workout by its archetype, anything else by exercise. Nothing here names a
package.
"""
from __future__ import annotations

from src import loader

SAME_AS = ('module', 'archetype', 'exercise')
SHOW = ('sets', 'reps', 'rounds', 'reps_per_round', 'weight', 'interval', 'time', 'hold', 'distance', 'rpe')
CHART = ('weight', 'reps', 'sets', 'total_reps', 'rounds', 'reps_per_round', 'time', 'hold', 'distance', 'rpe')
SUGGEST = ('confirm_pending', 'next_step', 'cycle_end', 'next_load', 'beat_last', 'standard_target', 'repeat_last')
SCOPE_KEYS = ('progression_models', 'modules', 'archetypes', 'exercises', 'slot_types', 'slot_roles',
              'named_workout', 'scored')
DEFAULT_HISTORY = 5

# Tried after a package's own entries, in this order.
DEFAULT_ENTRIES = (
    {'id': 'default_scored', 'scope': {'scored': True, 'named_workout': False}, 'same_as': 'exercise',
     'suggest': ['standard_target', 'beat_last']},
    {'id': 'default_cycle', 'scope': {'progression_models': ['density_cycle', 'timed_cycle', 'skill_hold']},
     'same_as': 'module', 'show': ['rounds', 'reps_per_round', 'interval', 'time', 'hold', 'weight'],
     'chart': 'total_reps', 'cycle': True, 'suggest': ['confirm_pending', 'next_step', 'cycle_end']},
    {'id': 'default_lift', 'scope': {'progression_models': ['load_per_exposure']}, 'same_as': 'exercise',
     'show': ['sets', 'reps', 'weight'], 'chart': 'weight', 'suggest': ['next_load', 'repeat_last']},
    {'id': 'default_volume', 'scope': {'progression_models': ['weekly_volume']}, 'same_as': 'module',
     'show': ['time', 'distance'], 'chart': 'time', 'suggest': ['next_step']},
    {'id': 'default_named', 'scope': {'named_workout': True}, 'same_as': 'archetype',
     'suggest': ['standard_target', 'beat_last']},
    {'id': 'default_exercise', 'same_as': 'exercise', 'suggest': ['next_step', 'repeat_last']},
)


@loader.scoped_cache
def _declared() -> dict:
    return loader.load_briefing_specs()


def clear_cache() -> None:
    """Forget loaded specs (tests that add a throwaway package call this)."""
    _declared.cache_clear()


def declared(package_id: str | None) -> dict:
    """The package's own briefing.yaml, or {} when it ships none."""
    return (_declared().get(package_id) or {}) if package_id else {}


def spec_for(package_id: str | None) -> dict:
    """{package, source: declared|default, entries}: the package's entries
    first, the defaults after them."""
    own = [e for e in (declared(package_id).get('entries') or []) if isinstance(e, dict)]
    return {'package': package_id, 'source': 'declared' if own else 'default',
            'entries': [_normal(e) for e in own] + [_normal(e) for e in DEFAULT_ENTRIES]}


def _normal(entry: dict) -> dict:
    same_as = entry.get('same_as') if entry.get('same_as') in SAME_AS else 'exercise'
    show = [k for k in entry.get('show') or [] if k in SHOW] or list(SHOW[:-1])
    chart = entry.get('chart') if entry.get('chart') in CHART else None
    history = entry.get('history')
    return {
        'id': entry.get('id'),
        'scope': {k: v for k, v in (entry.get('scope') or {}).items() if k in SCOPE_KEYS},
        'same_as': same_as,
        'show': show,
        'chart': chart,
        'history': history if isinstance(history, int) and not isinstance(history, bool) and history >= 0
        else DEFAULT_HISTORY,
        'cycle': bool(entry.get('cycle')),
        'suggest': [k for k in entry.get('suggest') or [] if k in SUGGEST],
        'notes': entry.get('notes') or None,
    }


def matches(entry: dict, facts: dict) -> bool:
    """Does an entry's scope hold for one exercise of a session? `facts`:
    progression_model, module, archetypes (the session's, and a templated
    day's named workouts), exercise, slot_type, slot_role, named_workout,
    scored."""
    scope = entry.get('scope') or {}
    for key, fact in (('progression_models', 'progression_model'), ('modules', 'module'),
                      ('exercises', 'exercise'), ('slot_types', 'slot_type'), ('slot_roles', 'slot_role')):
        if key in scope and facts.get(fact) not in (scope[key] or []):
            return False
    if 'archetypes' in scope and not set(scope['archetypes'] or []) & set(facts.get('archetypes') or []):
        return False
    for key in ('named_workout', 'scored'):
        if key in scope and bool(scope[key]) != bool(facts.get(key)):
            return False
    return True


def entry_for(spec: dict, facts: dict) -> dict:
    for entry in spec['entries']:
        if matches(entry, facts):
            return entry
    return _normal(DEFAULT_ENTRIES[-1])


def spec_errors(doc: dict, package_id: str, *, modules: set, archetypes: set, exercises: set) -> list[str]:
    """What tools/check_provenance.py reports for one briefing.yaml: its id,
    and scoped ids the package (with what it borrows) does not have."""
    where = f'{package_id}/briefing.yaml'
    problems = []
    if doc.get('id') != package_id:
        problems.append(f"{where}: id {doc.get('id')!r} must equal the package")
    seen = set()
    for entry in doc.get('entries') or []:
        if not isinstance(entry, dict):
            continue
        eid = entry.get('id')
        if eid in seen:
            problems.append(f'{where}: entry id {eid!r} is used twice')
        seen.add(eid)
        scope = entry.get('scope') or {}
        for key, known, what in (('modules', modules, 'training contract module'),
                                 ('archetypes', archetypes, 'archetype'),
                                 ('exercises', exercises, 'exercise')):
            for ref in scope.get(key) or []:
                if ref not in known:
                    problems.append(f'{where}: {eid!r} names {what} {ref!r}, which the package does not have')
    return problems
