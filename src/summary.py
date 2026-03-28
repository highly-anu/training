"""Per-week and per-phase volume summary computation and formatting."""
from __future__ import annotations

_STRENGTH_MODS   = {'max_strength', 'power', 'relative_strength', 'strength_endurance'}
_CARDIO_MODS     = {'aerobic_base', 'anaerobic_intervals', 'mixed_modal_conditioning'}
_DURABILITY_MODS = {'durability'}
_MOBILITY_MODS   = {'mobility', 'movement_skill'}


def _week_metrics(week_data: dict) -> dict:
    """Compute volume metrics for one week."""
    strength_sets = 0
    cond_minutes  = 0
    dur_minutes   = 0
    mob_minutes   = 0

    for day_sessions in week_data['schedule'].values():
        for session in day_sessions:
            modality = session.get('modality', '')
            arch = session.get('archetype') or {}
            arch_duration = arch.get('duration_estimate_minutes', 0) or 0
            exercises = session.get('exercises', [])

            if modality in _STRENGTH_MODS:
                strength_sets += sum(
                    ea['load']['sets']
                    for ea in exercises
                    if not ea.get('meta')
                    and ea.get('load')
                    and 'sets' in ea['load']
                )
            elif modality in _CARDIO_MODS:
                cond_minutes += arch_duration
            elif modality in _DURABILITY_MODS:
                dur_minutes += arch_duration
            elif modality in _MOBILITY_MODS:
                mob_minutes += arch_duration

    return {
        'strength_sets': strength_sets,
        'cond_minutes':  cond_minutes,
        'dur_minutes':   dur_minutes,
        'mob_minutes':   mob_minutes,
    }


def format_volume_summary(program: dict) -> str:
    """Render a volume summary table for the full program."""
    weeks = program.get('weeks', [])
    if not weeks:
        return ''

    rows = []
    for wk in weeks:
        m = _week_metrics(wk)
        rows.append({
            'week_number':   wk['week_number'],
            'week_in_phase': wk.get('week_in_phase', wk['week_number']),
            'phase':         wk['phase'],
            'is_deload':     wk.get('is_deload', False),
            **m,
        })

    def _fmt(v: int) -> str:
        return str(v) if v else '-'

    lines = ['## Volume Summary', '']
    lines.append('| Wk | Phase | Ph Wk | Str sets | Cond min | Dur min | Mob min | |')
    lines.append('|----|-------|-------|----------|----------|---------|---------|--|')

    prev_phase = None
    for r in rows:
        if r['phase'] != prev_phase:
            if prev_phase is not None:
                lines.append(f'| | *{prev_phase.title()} -> {r["phase"].title()}* | | | | | | |')
            prev_phase = r['phase']
        flag = 'D' if r['is_deload'] else ''
        lines.append(
            f"| {r['week_number']} "
            f"| {r['phase'].title()} "
            f"| {r['week_in_phase']} "
            f"| {_fmt(r['strength_sets'])} "
            f"| {_fmt(r['cond_minutes'])} "
            f"| {_fmt(r['dur_minutes'])} "
            f"| {_fmt(r['mob_minutes'])} "
            f"| {flag} |"
        )

    # Phase totals block
    lines.append('')
    lines.append('### Phase Totals')
    lines.append('')
    lines.append('| Phase | Weeks | Str sets/wk | Cond min/wk | Dur min/wk | Mob min/wk |')
    lines.append('|-------|-------|-------------|-------------|------------|------------|')

    phase_groups: dict[str, list] = {}
    for r in rows:
        phase_groups.setdefault(r['phase'], []).append(r)

    for phase, phase_rows in phase_groups.items():
        n = len(phase_rows)
        avg = lambda key: round(sum(r[key] for r in phase_rows) / n)  # noqa: E731
        lines.append(
            f"| {phase.title()} | {n} "
            f"| {avg('strength_sets')} "
            f"| {avg('cond_minutes')} "
            f"| {avg('dur_minutes')} "
            f"| {avg('mob_minutes')} |"
        )

    return '\n'.join(lines)
