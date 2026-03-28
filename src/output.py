"""Format a generated program as human-readable markdown."""
from __future__ import annotations

from .summary import format_volume_summary

_DAY_NAMES = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']


def _fmt_load(load: dict) -> str:
    """Convert a load dict to a compact readable string."""
    if not load:
        return ''
    parts = []

    if 'sets' in load and 'reps' in load:
        base = f"{load['sets']} × {load['reps']}"
        if 'weight_kg' in load:
            base += f" @ {load['weight_kg']} kg"
        elif 'target_rpe' in load:
            base += f" @ RPE {load['target_rpe']}"
        parts.append(base)

    if 'duration_minutes' in load and 'focus' not in load:
        # Skip standalone rendering when focus block will include the duration
        zone = load.get('zone_target', load.get('intensity', ''))
        s = f"{load['duration_minutes']} min"
        if zone:
            s += f" — {zone}"
        parts.append(s)

    if 'distance_km' in load:
        intensity = load.get('intensity', '')
        s = f"{load['distance_km']} km"
        if intensity:
            s += f" ({intensity})"
        parts.append(s)

    if 'distance_m' in load:
        intensity = load.get('intensity', '')
        s = f"{load['distance_m']}m"
        if intensity:
            s += f" ({intensity})"
        parts.append(s)

    if 'reps_per_round' in load:
        parts.append(f"{load['reps_per_round']} reps/round")

    if 'target_rounds' in load:
        fmt = load.get('format', 'AMRAP')
        parts.append(f"{load['time_minutes']} min {fmt} — target {load['target_rounds']} rounds")

    if 'hold_seconds' in load:
        parts.append(f"{load.get('sets', 3)} × {load['hold_seconds']}s hold")

    if 'focus' in load:
        duration = load.get('duration_minutes')
        s = f"{duration} min — " if duration else ''
        s += load['focus']
        parts.append(s)

    if 'load_note' in load:
        parts.append(load['load_note'])

    return ' | '.join(parts) if parts else ''


def _fmt_session(session: dict) -> str:
    """Format one session (archetype + exercises)."""
    if not session.get('archetype'):
        modality = session['modality'].replace('_', ' ').title()
        note = session.get('error', f'No archetype available for {modality} in this phase.')
        return f"#### Active Recovery\n*{modality} scheduled — {note}*\n"

    arch = session.get('archetype') or {}
    modality = session['modality'].replace('_', ' ').title()
    arch_name = arch.get('name', modality)
    duration = arch.get('duration_estimate_minutes', '?')
    is_deload = session.get('is_deload', False)
    deload_tag = ' *(deload)*' if is_deload else ''

    lines = [f"#### {arch_name}{deload_tag}"]
    lines.append(f"*{modality} · ~{duration} min*")
    lines.append('')

    exercises = session.get('exercises', [])
    if not exercises:
        lines.append('*No exercises assigned.*')
    else:
        for ea in exercises:
            # Skip meta/structural slots — they're annotated in the archetype notes
            if ea.get('meta'):
                continue
            ex = ea.get('exercise')
            if ex is None:
                role = ea.get('slot_role', 'slot').replace('_', ' ')
                err = ea.get('error', 'no exercise found')
                if ea.get('injury_skip'):
                    lines.append(f"- *({role} — {err})*")
                else:
                    lines.append(f"- ~~{role}~~: *{err}*")
                continue

            load = ea.get('load') or {}
            load_str = _fmt_load(load)
            role = ea.get('slot_role', '').replace('_', ' ')

            line = f"- **{ex['name']}**"
            if load_str:
                line += f" — {load_str}"
            if role:
                line += f"  *({role})*"
            lines.append(line)

    # Brief archetype note (first sentence only)
    raw_note = arch.get('notes', '').strip()
    if raw_note:
        first = raw_note.split('.')[0].strip() + '.'
        lines.append(f'\n> {first}')

    return '\n'.join(lines)


def _fmt_week(week_data: dict) -> str:
    """Format one week of training."""
    week_num = week_data['week_number']
    phase = week_data['phase'].title()
    is_deload = week_data['is_deload']
    schedule = week_data['schedule']

    deload_banner = ' *(Deload Week)*' if is_deload else ''
    lines = [f'## Week {week_num} — {phase} Phase{deload_banner}', '']

    for day_num in sorted(schedule.keys()):
        sessions = schedule[day_num]
        day_name = _DAY_NAMES[day_num - 1] if day_num <= 7 else f'Day {day_num}'

        lines.append(f'### {day_name}')
        if not sessions:
            lines.append('*Rest / active recovery*')
            lines.append('')
        else:
            for session in sessions:
                lines.append(_fmt_session(session))
                lines.append('')

    return '\n'.join(lines)


def format_program(
    program: dict,
    goal: dict,
    constraints: dict,
    validation,
) -> str:
    """Render the full program as a markdown string."""
    lines = [f"# Training Program: {goal['name']}", '', '---', '']
    lines.append('## Program Parameters')
    lines.append('')
    lines.append(f"| Parameter | Value |")
    lines.append(f"|-----------|-------|")
    lines.append(f"| Goal | {goal['name']} |")
    cal = constraints.get('event_calendar')
    weeks = program.get('weeks', [])
    is_full = len({w['phase'] for w in weeks}) > 1  # multi-phase output
    if cal and cal.get('weeks_until_event'):
        lines.append(f"| Event | {cal['weeks_until_event']}w away — "
                     f"program week {cal['week_in_program']}/{cal['total_weeks']} |")
    if is_full:
        phases_in_program = []
        seen = set()
        for w in weeks:
            p = w['phase']
            if p not in seen:
                phases_in_program.append(p)
                seen.add(p)
        lines.append(f"| Phases | {' -> '.join(phases_in_program)} |")
    else:
        lines.append(f"| Phase | {constraints.get('training_phase', 'base').title()} |")
    lines.append(f"| Days / week | {constraints['days_per_week']} |")
    lines.append(f"| Session length | {constraints.get('session_time_minutes', 75)} min |")
    lines.append(f"| Training level | {constraints.get('training_level', 'intermediate').title()} |")
    eq = ', '.join(constraints.get('equipment', []))
    lines.append(f"| Equipment | {eq} |")
    if constraints.get('injury_flags'):
        lines.append(f"| Injury flags | {', '.join(constraints['injury_flags'])} |")
    lines.append('')

    # Validation notices
    if not validation.feasible:
        lines.append('> **Generation blocked:**')
        for err in validation.errors:
            lines.append(f'> - {err["message"]}')
            if err.get('suggested_fix'):
                lines.append(f'>   *Fix: {err["suggested_fix"]}*')
        lines.append('')
        return '\n'.join(lines)

    if validation.warnings:
        lines.append('> **Notices:**')
        for w in validation.warnings:
            lines.append(f'> - {w["message"]}')
        lines.append('')

    if validation.info:
        for item in validation.info:
            lines.append(f'> {item["message"]}')
        lines.append('')

    lines.append('---')
    lines.append('')

    prev_phase = None
    for week_data in program.get('weeks', []):
        current_phase = week_data['phase']
        if current_phase != prev_phase:
            if prev_phase is not None:
                lines.append(f'> **Phase transition: {prev_phase.title()} -> {current_phase.title()}**')
                lines.append('')
            prev_phase = current_phase
        lines.append(_fmt_week(week_data))
        lines.append('---')
        lines.append('')

    summary = format_volume_summary(program)
    if summary:
        lines.append(summary)
        lines.append('')

    return '\n'.join(lines)
