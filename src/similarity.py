"""Pairwise likeness scores for each ontology category.

All scores are in [0, 1] where 1 = identical, 0 = completely different.
Each pair returns a dict:
    {score, primary: {label, detail, value}, secondary: {label, detail, value}}
"""
from __future__ import annotations

import heapq
import itertools
import math
import os
from src import loader

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _jaccard(a: set, b: set) -> float:
    if not a and not b:
        return 1.0
    union = a | b
    if not union:
        return 1.0
    return len(a & b) / len(union)


def _cosine(a: dict, b: dict) -> float:
    keys = set(a) | set(b)
    dot  = sum(a.get(k, 0.0) * b.get(k, 0.0) for k in keys)
    ma   = math.sqrt(sum(v * v for v in a.values()))
    mb   = math.sqrt(sum(v * v for v in b.values()))
    if ma == 0 or mb == 0:
        return 0.0
    return dot / (ma * mb)


def _range_overlap(min_a: float, max_a: float, min_b: float, max_b: float) -> float:
    overlap = max(0.0, min(max_a, max_b) - max(min_a, min_b))
    union   = max(max_a, max_b) - min(min_a, min_b)
    return overlap / union if union > 0 else 1.0


# ---------------------------------------------------------------------------
# Philosophy similarity
# ---------------------------------------------------------------------------

_INTENSITY_GROUPS = [
    {'autoregulation_rpe', 'operator_readiness'},
    {'hard_easy_alternation', 'polarized_80_20_uphill'},
    {'block_periodization', 'constant_variation'},
    {'linear_progression'},
    {'skill_based'},
]

_PROGRESSION_GROUPS = [
    {'volume_based', 'density_based'},
    {'load_based', 'range_based'},
    {'feel_based', 'rpm_based', 'time_based'},
    {'complexity_based'},
]


def _categorical_sim(a_val: str, b_val: str, groups: list[set]) -> float:
    if a_val == b_val:
        return 1.0
    for g in groups:
        if a_val in g and b_val in g:
            return 0.5
    return 0.0


def philosophy_similarity(a: dict, b: dict) -> dict:
    scope_a = set(a.get('scope', []))
    scope_b = set(b.get('scope', []))
    scope_sim = _jaccard(scope_a, scope_b)
    shared = len(scope_a & scope_b)
    total  = len(scope_a | scope_b)

    intensity_sim  = _categorical_sim(
        a.get('intensity_model', ''),
        b.get('intensity_model', ''),
        _INTENSITY_GROUPS,
    )
    progression_sim = _categorical_sim(
        a.get('progression_philosophy', ''),
        b.get('progression_philosophy', ''),
        _PROGRESSION_GROUPS,
    )
    style_sim = 0.5 * intensity_sim + 0.5 * progression_sim

    score = round(0.65 * scope_sim + 0.35 * style_sim, 4)

    same_intensity   = a.get('intensity_model') == b.get('intensity_model')
    same_progression = a.get('progression_philosophy') == b.get('progression_philosophy')
    if same_intensity and same_progression:
        style_detail = f"identical intensity model and progression philosophy"
    elif intensity_sim > 0 or progression_sim > 0:
        style_detail = f"similar training methodology"
    else:
        style_detail = f"different training methodology"

    return {
        'score': score,
        'primary': {
            'label': 'Scope overlap',
            'detail': f"{shared} of {total} modalities shared",
            'value': round(scope_sim, 4),
        },
        'secondary': {
            'label': 'Training style',
            'detail': style_detail,
            'value': round(style_sim, 4),
        },
    }


# ---------------------------------------------------------------------------
# Framework similarity
# ---------------------------------------------------------------------------

def framework_similarity(a: dict, b: dict) -> dict:
    spw_a = a.get('sessions_per_week') or {}
    spw_b = b.get('sessions_per_week') or {}

    total_a = sum(spw_a.values()) or 1
    total_b = sum(spw_b.values()) or 1
    vec_a = {k: v / total_a for k, v in spw_a.items()}
    vec_b = {k: v / total_b for k, v in spw_b.items()}
    modality_sim = _cosine(vec_a, vec_b)

    idist_a = a.get('intensity_distribution') or {}
    idist_b = b.get('intensity_distribution') or {}
    if idist_a and idist_b:
        keys = set(idist_a) | set(idist_b)
        l1   = sum(abs(idist_a.get(k, 0) - idist_b.get(k, 0)) for k in keys)
        intensity_sim = 1.0 - l1 / 2.0  # max L1 between two prob distributions = 2
        intensity_sim = max(0.0, min(1.0, intensity_sim))
    else:
        intensity_sim = 0.5  # unknown — neutral

    score = round(0.60 * modality_sim + 0.40 * intensity_sim, 4)

    shared_mods = set(spw_a) & set(spw_b)
    return {
        'score': score,
        'primary': {
            'label': 'Modality allocation',
            'detail': (
                f"share {len(shared_mods)} modality{'s' if len(shared_mods) != 1 else ''}"
                if shared_mods else "no shared modalities"
            ),
            'value': round(modality_sim, 4),
        },
        'secondary': {
            'label': 'Intensity distribution',
            'detail': (
                f"{'similar' if intensity_sim >= 0.7 else 'different'} zone distribution"
                if idist_a and idist_b else "intensity data unavailable"
            ),
            'value': round(intensity_sim, 4),
        },
    }


# ---------------------------------------------------------------------------
# Modality similarity
# ---------------------------------------------------------------------------

_COST_ORD = {'low': 0, 'medium': 1, 'high': 2}


def modality_similarity(a: dict, b: dict) -> dict:
    compat_a = set(a.get('compatible_in_session_with', []))
    compat_b = set(b.get('compatible_in_session_with', []))
    incompat_a = set(a.get('incompatible_in_session_with', []))
    incompat_b = set(b.get('incompatible_in_session_with', []))

    partner_sim = _jaccard(compat_a, compat_b)

    a_compat_b = b['id'] in compat_a
    b_compat_a = a['id'] in compat_b
    a_incompat_b = b['id'] in incompat_a or a['id'] in incompat_b
    if a_compat_b and b_compat_a:
        mutual_score = 1.0
        mutual_label = "mutually compatible"
    elif a_incompat_b:
        mutual_score = 0.0
        mutual_label = "mutually incompatible"
    else:
        mutual_score = 0.5
        mutual_label = "neutral pairing"

    cost_a = _COST_ORD.get(a.get('recovery_cost', 'medium'), 1)
    cost_b = _COST_ORD.get(b.get('recovery_cost', 'medium'), 1)
    cost_sim = 1.0 - abs(cost_a - cost_b) / 2.0

    compat_sim = 0.40 * partner_sim + 0.35 * cost_sim + 0.25 * mutual_score

    # Volume / session window overlap
    sess_a = a.get('typical_session_minutes') or {}
    sess_b = b.get('typical_session_minutes') or {}
    if sess_a and sess_b:
        session_sim = _range_overlap(sess_a['min'], sess_a['max'], sess_b['min'], sess_b['max'])
    else:
        session_sim = 0.5

    weekly_sim = _range_overlap(
        a.get('min_weekly_minutes', 0), a.get('max_weekly_minutes', 0),
        b.get('min_weekly_minutes', 0), b.get('max_weekly_minutes', 0),
    )
    volume_sim = 0.5 * session_sim + 0.5 * weekly_sim

    score = round(0.65 * compat_sim + 0.35 * volume_sim, 4)

    shared_partners = len(compat_a & compat_b)
    return {
        'score': score,
        'primary': {
            'label': 'Scheduling compatibility',
            'detail': (
                f"{shared_partners} shared compatible modalities; {mutual_label}"
            ),
            'value': round(compat_sim, 4),
        },
        'secondary': {
            'label': 'Volume profile',
            'detail': (
                f"{'similar' if volume_sim >= 0.5 else 'different'} session and weekly volume window"
            ),
            'value': round(volume_sim, 4),
        },
    }


# ---------------------------------------------------------------------------
# Archetype similarity
# ---------------------------------------------------------------------------

def _slot_patterns(arch: dict) -> set:
    patterns: set = set()
    for slot in arch.get('slots', []):
        if slot.get('skip_exercise'):
            continue
        ef = slot.get('exercise_filter') or {}
        if ef.get('movement_pattern'):
            patterns.add(ef['movement_pattern'])
        elif ef.get('category'):
            patterns.add(f"cat:{ef['category']}")
    return patterns


def archetype_similarity(a: dict, b: dict) -> dict:
    pat_a = _slot_patterns(a)
    pat_b = _slot_patterns(b)
    pattern_sim = _jaccard(pat_a, pat_b)
    shared_pats = len(pat_a & pat_b)
    total_pats  = len(pat_a | pat_b)

    mod_match  = 1.0 if a.get('modality') == b.get('modality') else 0.0
    equip_a    = set(a.get('required_equipment', [])) - {'open_space'}
    equip_b    = set(b.get('required_equipment', [])) - {'open_space'}
    equip_sim  = _jaccard(equip_a, equip_b)
    phase_sim  = _jaccard(set(a.get('applicable_phases', [])), set(b.get('applicable_phases', [])))
    level_sim  = _jaccard(set(a.get('training_levels', [])), set(b.get('training_levels', [])))
    logistics  = 0.30 * mod_match + 0.25 * equip_sim + 0.25 * phase_sim + 0.20 * level_sim

    score = round(0.55 * pattern_sim + 0.45 * logistics, 4)

    return {
        'score': score,
        'primary': {
            'label': 'Movement fingerprint',
            'detail': (
                f"{shared_pats} of {total_pats} slot patterns shared"
                if total_pats else "no movement patterns"
            ),
            'value': round(pattern_sim, 4),
        },
        'secondary': {
            'label': 'Logistical profile',
            'detail': (
                f"{'same' if mod_match else 'different'} modality; "
                f"{'similar' if logistics >= 0.6 else 'different'} equipment and phases"
            ),
            'value': round(logistics, 4),
        },
    }


# ---------------------------------------------------------------------------
# Exercise similarity
# ---------------------------------------------------------------------------

_EFFORT_ORD = {'low': 0, 'medium': 1, 'high': 2, 'max': 3}


def exercise_similarity(a: dict, b: dict) -> dict:
    pat_a = set(a.get('movement_patterns', []))
    pat_b = set(b.get('movement_patterns', []))
    # Special cases: both empty = same unknown bucket; one empty = 0
    if not pat_a and not pat_b:
        pattern_sim = 1.0
    elif not pat_a or not pat_b:
        pattern_sim = 0.0
    else:
        pattern_sim = _jaccard(pat_a, pat_b)

    mod_sim    = _jaccard(set(a.get('modality', [])), set(b.get('modality', [])))
    equip_a    = set(a.get('equipment', [])) - {'open_space'}
    equip_b    = set(b.get('equipment', [])) - {'open_space'}
    equip_sim  = _jaccard(equip_a, equip_b)
    effort_a   = _EFFORT_ORD.get(a.get('effort', ''), 1)
    effort_b   = _EFFORT_ORD.get(b.get('effort', ''), 1)
    effort_sim = 1.0 - abs(effort_a - effort_b) / 3.0
    bilateral  = 1.0 if a.get('bilateral') == b.get('bilateral') else 0.5
    cat_match  = 1.0 if a.get('category') == b.get('category') else 0.0
    context_sim = (
        0.30 * mod_sim
        + 0.25 * equip_sim
        + 0.20 * effort_sim
        + 0.15 * bilateral
        + 0.10 * cat_match
    )

    score = round(0.60 * pattern_sim + 0.40 * context_sim, 4)

    shared_pats = pat_a & pat_b
    return {
        'score': score,
        'primary': {
            'label': 'Movement patterns',
            'detail': (
                f"share {', '.join(sorted(shared_pats))}" if shared_pats
                else "no shared movement patterns"
            ),
            'value': round(pattern_sim, 4),
        },
        'secondary': {
            'label': 'Context',
            'detail': (
                f"{'same' if cat_match else 'different'} category; "
                f"{'same' if effort_sim == 1.0 else 'similar' if effort_sim >= 0.67 else 'different'} effort"
            ),
            'value': round(context_sim, 4),
        },
    }


# ---------------------------------------------------------------------------
# Movement pattern similarity
# ---------------------------------------------------------------------------

_MP_PATH = os.path.join(os.path.dirname(__file__), '..', 'data', 'commons', 'movement_patterns.yaml')


def _load_pattern_aliases() -> dict:
    with open(_MP_PATH, encoding='utf-8') as f:
        return loader.safe_load(f).get('aliases', {})


def _build_pattern_membership(aliases: dict) -> dict[str, set]:
    """Map each base pattern → set of alias names that reference it."""
    membership: dict[str, set] = {}
    for alias_name, defn in aliases.items():
        for base in defn.get('patterns', []):
            membership.setdefault(base, set()).add(alias_name)
    return membership


def movement_pattern_similarity(
    a_id: str,
    b_id: str,
    membership: dict[str, set],
    exercises: dict,
) -> dict:
    mem_a = membership.get(a_id, set())
    mem_b = membership.get(b_id, set())
    alias_sim = _jaccard(mem_a, mem_b)

    exs = list(exercises.values()) if isinstance(exercises, dict) else exercises
    exs_a = {ex['id'] for ex in exs if a_id in ex.get('movement_patterns', [])}
    exs_b = {ex['id'] for ex in exs if b_id in ex.get('movement_patterns', [])}
    cooccur_sim = _jaccard(exs_a, exs_b)

    score = round(0.50 * alias_sim + 0.50 * cooccur_sim, 4)

    shared_aliases = mem_a & mem_b
    shared_exs = len(exs_a & exs_b)
    total_exs  = len(exs_a | exs_b)

    return {
        'score': score,
        'primary': {
            'label': 'Alias membership',
            'detail': (
                f"both in {', '.join(sorted(shared_aliases))}" if shared_aliases
                else "no shared aliases"
            ),
            'value': round(alias_sim, 4),
        },
        'secondary': {
            'label': 'Exercise co-occurrence',
            'detail': f"{shared_exs} of {total_exs} exercises overlap",
            'value': round(cooccur_sim, 4),
        },
    }


# ---------------------------------------------------------------------------
# Top-level: compute all similarity matrices
# ---------------------------------------------------------------------------

TOP_N = 8


def _category(items: list[tuple[str, object]], pair, top: int) -> dict:
    """One category, compact: every pair's score once, explained only for each
    item's nearest ``top``.

    ``ids`` is the category in order and ``scores`` the upper triangle of the
    score matrix, row by row — (i, j) with i < j sits at
    ``i*n - i*(i+1)//2 + (j - i - 1)`` (``lib/similarity.pairIndex`` on the web).
    ``top[id]`` lists that item's nearest peers with the full result.

    The whole matrix with an explanation per pair (``{id_a: {id_b: result}}``)
    was 70 MB of JSON at 463 exercises, and building it took ~200 MB, which
    killed the 256 MB production worker on every Explore visit.
    """
    ids = [item_id for item_id, _ in items]
    scores: list[float] = []
    nearest: dict[str, list] = {item_id: [] for item_id in ids}
    for (i, (a_id, a)), (j, (b_id, b)) in itertools.combinations(enumerate(items), 2):
        sim = pair(a, b)
        scores.append(sim['score'])
        for here, there, k in ((a_id, b_id, j), (b_id, a_id, i)):
            heap = nearest[here]
            entry = (sim['score'], -k, there, sim)
            if len(heap) < top:
                heapq.heappush(heap, entry)
            elif entry[:2] > heap[0][:2]:
                heapq.heapreplace(heap, entry)
    return {
        'ids': ids,
        'scores': scores,
        'top': {
            item_id: [{'id': there, **sim}
                      for _, _, there, sim in sorted(heap, key=lambda e: e[:2], reverse=True)]
            for item_id, heap in nearest.items() if heap
        },
    }


def compute_all_similarities(
    philosophies: list,
    frameworks: dict,
    modalities: dict,
    archetypes: list,
    exercises: dict,
    top: int = TOP_N,
) -> dict:
    """Return {category: {ids, scores, top}} for every category (see ``_category``).

    Ties among the nearest go to the item listed first.
    """
    membership = _build_pattern_membership(_load_pattern_aliases())
    ex_list = list(exercises.values())

    def keyed(objs):
        return [(o['id'], o) for o in objs]

    return {
        'philosophies': _category(keyed(philosophies), philosophy_similarity, top),
        'frameworks':   _category(keyed(frameworks.values()), framework_similarity, top),
        'modalities':   _category(keyed(modalities.values()), modality_similarity, top),
        'archetypes':   _category(keyed(archetypes), archetype_similarity, top),
        'exercises':    _category(keyed(ex_list), exercise_similarity, top),
        # Base patterns only, derived from the alias table + exercises
        'movement_patterns': _category(
            [(pid, pid) for pid in membership],
            lambda a, b: movement_pattern_similarity(a, b, membership, ex_list),
            top,
        ),
    }
