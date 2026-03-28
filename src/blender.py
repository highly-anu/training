"""Blend multiple goals into one synthetic goal dict."""
from __future__ import annotations


def _merge_framework_selection(normalized: list, dominant_goal: dict) -> dict:
    """Union alternatives from all goals (deduped by framework_id), keeping dominant default."""
    base = dominant_goal.get('framework_selection', {})
    seen: set[str] = {alt['framework_id'] for alt in base.get('alternatives', [])}
    extra: list[dict] = []
    for goal, _ in normalized:
        if goal is dominant_goal:
            continue
        for alt in goal.get('framework_selection', {}).get('alternatives', []):
            fid = alt.get('framework_id')
            if fid and fid not in seen:
                seen.add(fid)
                extra.append(alt)
    if not extra:
        return base
    merged_alts = list(base.get('alternatives', [])) + extra
    return {**base, 'alternatives': merged_alts}


def blend_goals(goals_with_weights: list[dict]) -> tuple[dict, list[str]]:
    """
    Args:
        goals_with_weights: [{'goal': goal_dict, 'weight': float}, ...]
    Returns:
        (merged_goal_dict, incompatibility_warning_strings)
    """
    total = sum(gw['weight'] for gw in goals_with_weights)
    normalized = [(gw['goal'], gw['weight'] / total) for gw in goals_with_weights]
    dominant_goal = max(normalized, key=lambda x: x[1])[0]

    # Incompatibility check
    selected_ids = {goal['id'] for goal, _ in normalized}
    warnings: list[str] = []
    seen_pairs: set[tuple] = set()
    for goal, _ in normalized:
        for incompat in goal.get('incompatible_with', []):
            incompat_id = incompat.get('goal_id', '') if isinstance(incompat, dict) else str(incompat)
            reason = incompat.get('reason', '').strip() if isinstance(incompat, dict) else ''
            if incompat_id in selected_ids:
                pair = tuple(sorted([goal['id'], incompat_id]))
                if pair not in seen_pairs:
                    seen_pairs.add(pair)
                    warnings.append(f"{goal['name']} conflicts with {incompat_id}. {reason}")

    # Blend base priorities
    all_mods: set[str] = set()
    for goal, _ in normalized:
        all_mods.update(goal.get('priorities', {}).keys())
    blended: dict[str, float] = {
        mod: sum(goal.get('priorities', {}).get(mod, 0) * w for goal, w in normalized)
        for mod in all_mods
    }
    total_p = sum(blended.values()) or 1
    blended = {k: round(v / total_p, 3) for k, v in blended.items()}

    # Blend phase_sequence from dominant goal
    blended_phases = []
    for phase_entry in dominant_goal.get('phase_sequence', []):
        phase_name = phase_entry['phase']
        override: dict[str, float] = {}
        for goal, w in normalized:
            phase_prio: dict = goal.get('priorities', {})
            for ph in goal.get('phase_sequence', []):
                if ph['phase'] == phase_name:
                    phase_prio = ph.get('priority_override') or goal.get('priorities', {})
                    break
            for mod, val in phase_prio.items():
                override[mod] = override.get(mod, 0) + val * w
        total_o = sum(override.values()) or 1
        override = {k: round(v / total_o, 3) for k, v in override.items()}
        blended_phases.append({**phase_entry, 'priority_override': override})

    # Union sources; stricter prereqs
    sources = list({src for goal, _ in normalized for src in goal.get('primary_sources', [])})
    prereqs: dict = {}
    for goal, _ in normalized:
        for k, v in goal.get('minimum_prerequisites', {}).items():
            if k not in prereqs or v > prereqs[k]:
                prereqs[k] = v

    names = [goal['name'] for goal, _ in normalized]
    merged = {
        'id': '_blended',
        'name': ' + '.join(names),
        'description': f"Combined program blending {len(normalized)} goals.",
        'priorities': blended,
        'phase_sequence': blended_phases,
        'framework_selection': _merge_framework_selection(normalized, dominant_goal),
        'primary_sources': sources,
        'minimum_prerequisites': prereqs,
        'incompatible_with': [],
        'notes': f"Blended from: {', '.join(names)}.",
        'event_date': dominant_goal.get('event_date'),
    }
    return merged, warnings
