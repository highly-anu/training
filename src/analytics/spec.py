"""What progress means for a program: the composed analytics spec.

A package may declare it (`data/packages/<id>/analytics.yaml`, schema in
docs/schemas/analytics.schema.json). When it does not, one is synthesised
from the package's frameworks: each committed or core modality gets the
default primitive for the *modality's* `progression_model` — the modality's,
not the framework's, because `src/generator.py:360-363` builds `prog_model_for`
from the modality yaml and that is the model that actually wrote `ea.load`.

For a blend the specs of every philosophy in `goal.primary_sources` compose;
each entry carries its philosophy and that philosophy's weight, which is the
first real use of the `philosophy_weights` the old tracker accepted and never
read.

Scope resolution lives here too, so a primitive never has to know how a spec
selects its sessions: `select(entry, weeks)` hands each primitive the exact
(week, session, assignments) triples it should look at.
"""
from __future__ import annotations

import fnmatch
from dataclasses import dataclass, field

from src import loader

PRIMITIVES = (
    'set_load', 'load_at_rpe', 'rounds', 'duration', 'distance', 'hold_seconds',
    'rate', 'zone_minutes', 'aerobic_efficiency', 'unlocks', 'benchmark_level',
    'session_completion',
)

# modality progression_model → (primitive, expected). The reference for what
# each model's native currency is; see the plan's table.
DEFAULT_FOR_MODEL: dict[str, tuple[str, object]] = {
    'linear_load':           ('set_load',     'achieved_plus_increment'),
    'volume_block':          ('set_load',     'prescribed'),
    'rpe_autoregulation':    ('load_at_rpe',  'prescribed'),
    'density':               ('rounds',       {'load_field': 'target_rounds'}),
    'time_to_task':          ('duration',     {'load_field': 'duration_minutes'}),
    'intensity_split_shift': ('zone_minutes', {'framework_field': 'intensity_distribution'}),
    'complexity':            ('unlocks',      'none'),
    'pentathlon_rpm':        ('rate',         'none'),
    'range_progression':     ('hold_seconds', {'load_field': 'hold_seconds'}),
}

# philosophy progression_philosophy → the primitive its section leads with.
HEADLINE_FOR_PHILOSOPHY: dict[str, str] = {
    'load_based':       'set_load',
    'feel_based':       'load_at_rpe',
    'density_based':    'rounds',
    'time_based':       'duration',
    'volume_based':     'duration',
    'complexity_based': 'unlocks',
    'rpm_based':        'rate',
    'range_based':      'hold_seconds',
}

# Roles that are not the work a load-based methodology measures itself by.
PREPARATORY_ROLE_GLOBS = ('*warm*', '*cool*', '*prep*', '*accessory*', '*finisher*',
                          '*tissue*', '*mobility*', '*activation*')

DEFAULT_BALANCE = [
    {'a': 'push', 'b': 'pull', 'min': 0.6, 'max': 1.6},
    {'a': 'hinge', 'b': 'squat', 'min': 0.5, 'max': 1.5},
]


@dataclass
class Entry:
    id: str
    primitive: str
    philosophy: str
    weight: float = 1.0
    source: str = 'default'            # declared | default
    label: str = ''
    scope: dict = field(default_factory=dict)
    expected: object = 'none'
    stall: dict | None = None
    headline: bool = False
    benchmarks: list = field(default_factory=list)
    target_level: str | None = None
    rpm_target: float | None = None
    min_sessions: int = 2
    notes: str = ''


@dataclass
class Spec:
    philosophy: str
    source: str                         # declared | default
    entries: list
    balance: list                       # declared warnings; [] means information only
    balance_declared: bool
    benchmarks: list


# ── Loading and synthesis ────────────────────────────────────────────────────

def declared(package_id: str) -> dict | None:
    return loader.load_analytics_specs().get(package_id)


def spec_for(package_id: str, *, frameworks: dict | None = None,
             modalities: dict | None = None, philosophy: dict | None = None,
             weight: float = 1.0) -> Spec:
    """The spec for one philosophy: its declared file, else a synthesised default."""
    raw = declared(package_id)
    if raw is not None:
        return _from_declared(raw, package_id, weight, philosophy)
    return _synthesise(package_id, frameworks or loader.load_all_frameworks(),
                       modalities or loader.load_all_modalities(),
                       philosophy or _philosophy(package_id), weight)


def _from_declared(raw: dict, package_id: str, weight: float, philosophy: dict | None) -> Spec:
    entries = []
    for item in raw.get('progress') or []:
        entries.append(Entry(
            id=item['id'], primitive=item['primitive'], philosophy=package_id,
            weight=weight, source='declared', label=item.get('label') or item['id'],
            scope=dict(item.get('scope') or {}), expected=item.get('expected', 'none'),
            stall=item.get('stall'), headline=bool(item.get('headline')),
            benchmarks=list(item.get('benchmarks') or []),
            target_level=item.get('target_level'), rpm_target=item.get('rpm_target'),
            min_sessions=int(item.get('min_sessions') or 2), notes=item.get('notes') or '',
        ))
    _mark_headline(entries, philosophy or _philosophy(package_id))
    balance = list((raw.get('movement') or {}).get('balance') or [])
    return Spec(package_id, 'declared', entries, balance, bool(balance),
                list(raw.get('benchmarks') or []))


def _synthesise(package_id: str, frameworks: dict, modalities: dict,
                philosophy: dict | None, weight: float) -> Spec:
    """A spec from the package's frameworks: one entry per governed modality."""
    entries: list[Entry] = []
    seen: set[tuple] = set()
    own = [fw for fw in frameworks.values() if fw.get('source_philosophy') == package_id]
    for fw in own:
        tiers = fw.get('modality_priority') or {}
        governed = list(tiers.get('committed') or []) + list(tiers.get('core') or [])
        if not governed:
            governed = list((fw.get('sessions_per_week') or {}).keys())
        for modality in governed:
            model = (modalities.get(modality) or {}).get('progression_model', 'linear_load')
            primitive, expected = DEFAULT_FOR_MODEL.get(model, ('duration', 'prescribed'))
            key = (modality, primitive)
            if key in seen:
                continue
            seen.add(key)
            scope: dict = {'modalities': [modality]}
            if primitive in ('set_load', 'load_at_rpe'):
                # Measure the working sets, not the warm-up. Slot roles are
                # free-form — 144 distinct strings across the packages, and
                # Starting Strength's own are primary_squat / upper_press /
                # secondary_compound — so the default excludes preparatory and
                # accessory roles rather than guessing which names mean "main".
                scope['slot_types'] = ['sets_reps']
                scope['exclude_slot_roles'] = list(PREPARATORY_ROLE_GLOBS)
            entries.append(Entry(
                id=f'{modality}_{primitive}', primitive=primitive, philosophy=package_id,
                weight=weight, source='default',
                label=f"{modality.replace('_', ' ').title()} — {primitive.replace('_', ' ')}",
                scope=scope, expected=expected,
            ))
    _mark_headline(entries, philosophy)
    return Spec(package_id, 'default', entries, [], False, [])


def _mark_headline(entries: list[Entry], philosophy: dict | None) -> None:
    if any(e.headline for e in entries) or not entries:
        return
    want = HEADLINE_FOR_PHILOSOPHY.get((philosophy or {}).get('progression_philosophy') or '')
    for e in entries:
        if e.primitive == want:
            e.headline = True
            return
    entries[0].headline = True


def _philosophy(package_id: str) -> dict:
    try:
        return loader.load_philosophy(package_id)
    except (FileNotFoundError, KeyError):
        return {}


# ── Composition across a blend ───────────────────────────────────────────────

def compose(goal: dict, philosophy_weights: dict | None = None) -> list[Spec]:
    """One Spec per philosophy in the goal, weighted; primary first."""
    sources = [p for p in (goal.get('primary_sources') or []) if p]
    weights = philosophy_weights or {}
    frameworks = loader.load_all_frameworks()
    modalities = loader.load_all_modalities()
    specs = []
    for pid in sources:
        specs.append(spec_for(pid, frameworks=frameworks, modalities=modalities,
                              philosophy=_philosophy(pid),
                              weight=float(weights.get(pid, 1.0 if len(sources) == 1 else 0.0) or 0.0)))
    return specs


# ── Scope resolution ─────────────────────────────────────────────────────────

def framework_id_of(week: dict) -> str | None:
    fw = week.get('framework')
    if isinstance(fw, dict):
        return fw.get('id')
    return fw


def session_in_scope(entry: Entry, week: dict, session: dict) -> bool:
    scope = entry.scope or {}
    if scope.get('frameworks') and framework_id_of(week) not in scope['frameworks']:
        return False
    if scope.get('modalities') and session.get('modality') not in scope['modalities']:
        return False
    if scope.get('archetypes'):
        arch_id = (session.get('archetype') or {}).get('id')
        if arch_id not in scope['archetypes']:
            return False
    return True


def assignments_in_scope(entry: Entry, session: dict) -> list[dict]:
    """The exercise assignments an entry looks at inside a session it selected.

    Meta rows, injury skips and coverage gaps are never work the athlete did.
    """
    scope = entry.scope or {}
    out = []
    for ea in session.get('exercises') or []:
        if ea.get('meta') or ea.get('injury_skip') or ea.get('coverage_gap'):
            continue
        ex = ea.get('exercise') or {}
        if not ex.get('id'):
            continue
        role = ea.get('slot_role') or ''
        if scope.get('slot_roles') and not any(fnmatch.fnmatch(role, pat) for pat in scope['slot_roles']):
            continue
        if scope.get('exclude_slot_roles') and any(fnmatch.fnmatch(role, pat)
                                                    for pat in scope['exclude_slot_roles']):
            continue
        if scope.get('slot_types') and ea.get('slot_type') not in scope['slot_types']:
            continue
        if scope.get('exercises') and ex['id'] not in scope['exercises']:
            continue
        if scope.get('movement_patterns'):
            patterns = set(ex.get('movement_patterns') or [])
            if not patterns & set(scope['movement_patterns']):
                continue
        out.append(ea)
    return out


def select(entry: Entry, weeks: list[dict]) -> list[dict]:
    """[{week, week_index, day, session_index, session, assignments}] for an entry."""
    hits = []
    for week_index, week in enumerate(weeks or []):
        for day, sessions in (week.get('schedule') or {}).items():
            for session_index, session in enumerate(sessions or []):
                if not session_in_scope(entry, week, session):
                    continue
                hits.append({
                    'week': week, 'week_index': week_index, 'day': day,
                    'session_index': session_index, 'session': session,
                    'assignments': assignments_in_scope(entry, session),
                })
    return hits
