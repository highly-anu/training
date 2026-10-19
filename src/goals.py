"""Build synthetic goal dicts from philosophy packages.

A "goal" is the engine's internal request object: priorities, a phase sequence,
and a framework selection. Philosophies are the authored input; this module is
the single place that translates one (or a weighted blend) into a goal.

A goal is built from one **track** of one philosophy (src/phases.py): the
track's phases become `phase_sequence`, each carrying its kind, its own id and
text, and the framework that builds its weeks. There is no default sequence —
a philosophy that declares no track cannot be turned into a goal, rather than
being handed a base/build/peak it does not teach.

Kept out of api.py deliberately — the test scripts and the provenance checker
must exercise exactly the same construction the HTTP layer uses.
"""
from __future__ import annotations

from . import loader, phases


class FrameworkResolutionError(Exception):
    """A philosophy declares no usable framework."""


def _ordered_unique(items) -> list:
    seen: set = set()
    out: list = []
    for it in items:
        if it and it not in seen:
            seen.add(it)
            out.append(it)
    return out


def declared_framework_ids(phil: dict, all_frameworks: list) -> list:
    """Every framework id this philosophy claims, in declaration order.

    The frameworks its tracks' phases run, then any framework whose YAML names
    this philosophy as `source_philosophy` (so a framework file not yet placed
    in a phase is still recognised as owned rather than as another's).
    """
    phil_id = phil.get('id')
    ids = phases.framework_ids_of(phil)
    ids.extend(
        f['id'] for f in all_frameworks if f.get('source_philosophy') == phil_id
    )
    return _ordered_unique(ids)


def select_track(phil: dict, track_id: str | None = None) -> dict:
    """The requested track, else the philosophy's primary track."""
    if not phases.tracks_of(phil):
        raise FrameworkResolutionError(
            f"Philosophy '{phil.get('id')}' declares no tracks. Add a `tracks` "
            f"entry (phases with a kind and a framework_id) to its philosophy.yaml."
        )
    if track_id:
        track = phases.find_track(phil, track_id)
        if track is None:
            raise phases.PhaseResolutionError(
                f"Philosophy '{phil.get('id')}' has no track '{track_id}': "
                f"{[t.get('id') for t in phases.tracks_of(phil)]}"
            )
        return track
    return phases.primary_track(phil)


def _main_framework(track: dict) -> str | None:
    """The framework of the track's longest phase (the first on a tie).

    It stands for the track where one framework must: the goal's priority
    vector and the selection default. For Uphill that is the base phase, which
    is what `primary_framework_id` used to name by hand.
    """
    best = None
    for ph in track.get('phases') or []:
        if best is None or int(ph.get('weeks') or 1) > int(best.get('weeks') or 1):
            best = ph
    return (best or {}).get('framework_id')


def resolve_primary_framework(phil: dict, all_frameworks: list) -> str:
    """The philosophy's default framework: the main framework of its primary track."""
    declared = declared_framework_ids(phil, all_frameworks)
    if not declared:
        raise FrameworkResolutionError(
            f"Philosophy '{phil.get('id')}' declares no framework. Add a "
            f"`tracks` entry whose phases name a framework_id."
        )
    track = phases.primary_track(phil)
    main = _main_framework(track) if track else None
    return main or declared[0]


def build_framework_selection(phil: dict, all_frameworks: list,
                              track: dict | None = None) -> dict:
    """`{default_framework, alternatives}` covering every framework the philosophy uses.

    Inside a track every phase names its own framework, so selection never
    falls back to these; alternatives exist so the validator recognises every
    one of the philosophy's frameworks as owned.
    """
    default_id = (_main_framework(track) if track else None) \
        or resolve_primary_framework(phil, all_frameworks)
    alternatives = [
        {'framework_id': fid, 'condition': ''}
        for fid in declared_framework_ids(phil, all_frameworks)
        if fid != default_id
    ]
    return {'default_framework': default_id, 'alternatives': alternatives}


def philosophy_to_goal(phil_id: str, all_frameworks: list,
                       track_id: str | None = None) -> dict:
    """Build a synthetic goal dict from one track of a philosophy."""
    phil = loader.load_philosophy(phil_id)
    track = select_track(phil, track_id)

    framework_selection = build_framework_selection(phil, all_frameworks, track)
    main_fw_id = framework_selection['default_framework']

    # Priorities come from the track's main framework's weekly session mix.
    main_fw = next((f for f in all_frameworks if f['id'] == main_fw_id), None)
    sessions = (main_fw or {}).get('sessions_per_week', {})
    total = sum(sessions.values()) or 1
    priorities = {mod: count / total for mod, count in sessions.items()}

    if not priorities:
        bias = phil.get('bias', phil.get('scope', []))
        n = len(bias) or 1
        priorities = {mod: 1.0 / n for mod in bias}

    from .training_contract import load_contract
    contract = load_contract(phil_id, track['id'])
    return {
        'id': f'_phil_{phil_id}',
        'name': phil.get('name', phil_id),
        'priorities': priorities,
        'track': {
            'id': track.get('id'),
            'name': track.get('name'),
            'description': track.get('description'),
            'philosophy_id': phil_id,
        },
        'phase_sequence': phases.phase_sequence_for(track),
        'framework_selection': framework_selection,
        'primary_sources': [phil_id],
        'minimum_prerequisites': {},
        **({'training_contract': contract} if contract else {}),
        'incompatible_with': [],
        'notes': phil.get('notes', ''),
    }


def _track_owner(phil_ids: list, track_id: str | None, ordered: list) -> str | None:
    """The member philosophy that owns `track_id`, heaviest first."""
    if not track_id:
        return None
    for pid in ordered:
        if phases.find_track(loader.load_philosophy(pid), track_id):
            return pid
    raise phases.PhaseResolutionError(
        f"No philosophy in {phil_ids} has a track '{track_id}'."
    )


def blend_philosophy_goals(phil_ids: list, phil_weights: dict, all_frameworks: list,
                           track_id: str | None = None) -> dict:
    """Weighted-average a set of philosophy synthetic goals into one.

    Phases are not blended: a program follows one philosophy's track. That is
    the dominant (heaviest) member's primary track, unless `track_id` names a
    track of any member, in which case that member's track runs and its
    phases and words are the program's. Only the priority vector is averaged.
    """
    total_w = sum(phil_weights.get(pid, 1.0 / len(phil_ids)) for pid in phil_ids)
    blended_priorities: dict = {}
    ordered = sorted(phil_ids, key=lambda pid: -phil_weights.get(pid, 1.0 / len(phil_ids)))
    owner = _track_owner(phil_ids, track_id, ordered) or ordered[0]
    primary_goal = philosophy_to_goal(owner, all_frameworks, track_id=track_id)

    for pid in phil_ids:
        w = phil_weights.get(pid, 1.0 / len(phil_ids)) / total_w
        g = philosophy_to_goal(pid, all_frameworks)
        for mod, val in g['priorities'].items():
            blended_priorities[mod] = blended_priorities.get(mod, 0.0) + val * w

    p_total = sum(blended_priorities.values()) or 1.0
    blended_priorities = {k: v / p_total for k, v in blended_priorities.items()}

    # Every member philosophy's frameworks are recognised in a blend.
    default_id = primary_goal['framework_selection']['default_framework']
    alt_ids: list = []
    for pid in phil_ids:
        phil = loader.load_philosophy(pid)
        alt_ids.extend(declared_framework_ids(phil, all_frameworks))
    alternatives = [
        {'framework_id': fid, 'condition': ''}
        for fid in _ordered_unique(alt_ids)
        if fid != default_id
    ]

    result = dict(primary_goal)
    # A contract fixes one method's modules; a blend averages several methods'
    # priorities, so it is built by the general generator (a Wildman-led blend
    # used to be refused as "one methodology at a time").
    result.pop('training_contract', None)
    result['id'] = '_phil_blend'
    result['name'] = ' + '.join(
        loader.load_philosophy(pid).get('name', pid).split(' /')[0].split(' —')[0].strip()
        for pid in phil_ids
    )
    result['priorities'] = blended_priorities
    result['primary_sources'] = phil_ids
    result['framework_selection'] = {
        'default_framework': default_id,
        'alternatives': alternatives,
    }
    return result


def owner_track_for_framework(phil_ids: list, phil_weights: dict | None,
                              framework_id: str) -> tuple[str, dict, dict] | None:
    """(philosophy id, track, first phase) that runs `framework_id`, heaviest member first."""
    weights = phil_weights or {}
    ordered = sorted(phil_ids, key=lambda pid: -weights.get(pid, 1.0 / max(1, len(phil_ids))))
    for pid in ordered:
        hit = phases.track_for_framework(loader.load_philosophy(pid), framework_id)
        if hit:
            return pid, hit[0], hit[1]
    return None
