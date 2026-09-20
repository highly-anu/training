"""Build synthetic goal dicts from philosophy packages.

A "goal" is the engine's internal request object: priorities, a phase sequence,
and a framework selection. Philosophies are the authored input; this module is
the single place that translates one (or a weighted blend) into a goal.

Kept out of api.py deliberately — the test scripts and the provenance checker
must exercise exactly the same construction the HTTP layer uses.
"""
from __future__ import annotations

from . import loader


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

    Sources, in priority order:
      1. primary_framework_id
      2. framework_groups[].frameworks — both `alternatives` and `sequential`
      3. canonical_phase_sequence[].framework_id (group-level and legacy top-level)
      4. frameworks whose YAML declares source_philosophy == this philosophy

    (2) is the one that used to be ignored, which made every non-primary
    training style invisible to the validator.
    """
    phil_id = phil.get('id')
    ids: list = [phil.get('primary_framework_id')]

    for group in phil.get('framework_groups', []) or []:
        ids.extend(group.get('frameworks', []) or [])
        for entry in group.get('canonical_phase_sequence', []) or []:
            ids.append(entry.get('framework_id'))

    for entry in phil.get('canonical_phase_sequence', []) or []:
        ids.append(entry.get('framework_id'))

    ids.extend(
        f['id'] for f in all_frameworks if f.get('source_philosophy') == phil_id
    )
    return _ordered_unique(ids)


def resolve_primary_framework(phil: dict, all_frameworks: list) -> str:
    """The philosophy's default framework.

    Honours `primary_framework_id` first. Previously the synthetic-phase branch
    ignored it and took whichever framework file globbed first, which gave
    wildman_kettlebell `kb_pentathlon` instead of its declared
    `kb_general_practice`.
    """
    declared = declared_framework_ids(phil, all_frameworks)
    if not declared:
        raise FrameworkResolutionError(
            f"Philosophy '{phil.get('id')}' declares no framework. Add "
            f"primary_framework_id or a framework_groups entry to its philosophy.yaml."
        )

    primary = phil.get('primary_framework_id')
    if primary:
        if primary not in declared:
            raise FrameworkResolutionError(
                f"Philosophy '{phil.get('id')}' declares primary_framework_id "
                f"'{primary}', which is not one of its frameworks: {declared}."
            )
        return primary

    sequential = next(
        (g for g in phil.get('framework_groups', []) or [] if g.get('type') == 'sequential'),
        None,
    )
    if sequential and sequential.get('frameworks'):
        return sequential['frameworks'][0]
    return declared[0]


def build_framework_selection(phil: dict, all_frameworks: list) -> dict:
    """`{default_framework, alternatives}` covering every style the philosophy offers.

    Alternatives carry an empty condition: `_eval_condition('')` is False, so they
    are never auto-selected — they exist so an explicit `framework_id` from the
    builder is recognised as owned rather than rejected as another philosophy's.
    """
    default_id = resolve_primary_framework(phil, all_frameworks)
    alternatives = [
        {'framework_id': fid, 'condition': ''}
        for fid in declared_framework_ids(phil, all_frameworks)
        if fid != default_id
    ]
    return {'default_framework': default_id, 'alternatives': alternatives}


def philosophy_to_goal(phil_id: str, all_frameworks: list) -> dict:
    """Build a synthetic goal dict from a philosophy's framework_groups."""
    phil = loader.load_philosophy(phil_id)

    groups = phil.get('framework_groups', []) or []
    sequential_group = next((g for g in groups if g.get('type') == 'sequential'), None)

    framework_selection = build_framework_selection(phil, all_frameworks)
    primary_fw_id = framework_selection['default_framework']

    if sequential_group and sequential_group.get('canonical_phase_sequence'):
        seq = sequential_group['canonical_phase_sequence']
    elif phil.get('canonical_phase_sequence'):
        seq = phil['canonical_phase_sequence']
    else:
        seq = [
            {'phase': 'base', 'weeks': 8},
            {'phase': 'build', 'weeks': 6},
            {'phase': 'peak', 'weeks': 4},
        ]

    # Priorities come from the primary framework's weekly session mix.
    primary_fw = next((f for f in all_frameworks if f['id'] == primary_fw_id), None)
    sessions = (primary_fw or {}).get('sessions_per_week', {})
    total = sum(sessions.values()) or 1
    priorities = {mod: count / total for mod, count in sessions.items()}

    if not priorities:
        bias = phil.get('bias', phil.get('scope', []))
        n = len(bias) or 1
        priorities = {mod: 1.0 / n for mod in bias}

    return {
        'id': f'_phil_{phil_id}',
        'name': phil.get('name', phil_id),
        'priorities': priorities,
        'phase_sequence': [
            {
                'phase': e.get('phase', 'base'),
                'weeks': e.get('weeks', 8),
                'framework_id': e.get('framework_id'),
                'focus': e.get('focus'),
            }
            for e in seq
        ],
        'framework_selection': framework_selection,
        'primary_sources': [phil_id],
        'minimum_prerequisites': {},
        'incompatible_with': [],
        'notes': phil.get('notes', ''),
    }


def blend_philosophy_goals(phil_ids: list, phil_weights: dict, all_frameworks: list) -> dict:
    """Weighted-average a set of philosophy synthetic goals into one."""
    total_w = sum(phil_weights.get(pid, 1.0 / len(phil_ids)) for pid in phil_ids)
    blended_priorities: dict = {}
    primary_phil_id = max(phil_ids, key=lambda pid: phil_weights.get(pid, 1.0 / len(phil_ids)))
    primary_goal = philosophy_to_goal(primary_phil_id, all_frameworks)

    for pid in phil_ids:
        w = phil_weights.get(pid, 1.0 / len(phil_ids)) / total_w
        g = philosophy_to_goal(pid, all_frameworks)
        for mod, val in g['priorities'].items():
            blended_priorities[mod] = blended_priorities.get(mod, 0.0) + val * w

    p_total = sum(blended_priorities.values()) or 1.0
    blended_priorities = {k: v / p_total for k, v in blended_priorities.items()}

    # Every member philosophy's styles are selectable in a blend.
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
