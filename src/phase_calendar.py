"""Phase calendar — compute current training phase from an event date."""
from __future__ import annotations

import math
from datetime import date

from . import phases


def compute_phase_from_date(
    goal: dict,
    event_date: date,
    today: date | None = None,
) -> dict:
    """
    Walk the goal's phase_sequence backward from the event date to determine
    which phase and week the athlete is in today.

    Returns a dict with:
        phase            : str  — current phase kind
        phase_id         : str  — current phase's id in the track
        week_in_phase    : int  — 1-indexed week within the current phase
        week_in_program  : int  — 1-indexed overall program week
        total_weeks      : int  — sum of all phase weeks in the sequence
        weeks_until_event: int  — weeks remaining until the event
        phase_sequence   : list — the goal's phase_sequence
        message          : str  — human-readable one-liner summary
    """
    if today is None:
        today = date.today()

    sequence = goal.get('phase_sequence', [])
    if not sequence:
        raise phases.PhaseResolutionError('The goal has no phase sequence.')

    days_until = (event_date - today).days

    if days_until <= 0:
        last = sequence[-1]
        total = sum(p.get('weeks', 1) for p in sequence)
        return {
            'phase': last['phase'],
            'phase_id': last.get('phase_id'),
            'week_in_phase': last.get('weeks', 1),
            'week_in_program': total,
            'total_weeks': total,
            'weeks_until_event': 0,
            'phase_sequence': sequence,
            'message': 'Event date has passed. Placing you at the final phase/week.',
        }

    weeks_until = max(1, math.ceil(days_until / 7))
    total_weeks = sum(p.get('weeks', 1) for p in sequence)

    # Program week you'd be at if the full sequence started `total_weeks` weeks ago
    program_week = total_weeks - weeks_until + 1
    if program_week < 1:
        program_week = 1  # before program start — begin at week 1 of first phase

    # Walk the sequence to find which phase contains program_week
    cumulative = 0
    current = sequence[0]
    week_in_phase = 1
    for entry in sequence:
        phase_weeks = entry.get('weeks', 1)
        if cumulative + phase_weeks >= program_week:
            current = entry
            week_in_phase = program_week - cumulative
            break
        cumulative += phase_weeks
    else:
        # program_week exceeds total — clamp to final phase, final week
        current = sequence[-1]
        week_in_phase = current.get('weeks', 1)
    current_phase = current['phase']
    current_name = current.get('name') or current.get('phase_id') or current_phase

    seq_str = ' -> '.join(
        f"{p.get('name') or p.get('phase_id') or p['phase']}({p.get('weeks', '?')}w)"
        for p in sequence
    )
    plural = 's' if weeks_until != 1 else ''
    message = (
        f"Event in {weeks_until} week{plural} | "
        f"Program week {program_week}/{total_weeks} | "
        f"Phase: {current_name}, week {week_in_phase} | "
        f"Sequence: {seq_str}"
    )

    return {
        'phase': current_phase,
        'phase_id': current.get('phase_id'),
        'week_in_phase': week_in_phase,
        'week_in_program': program_week,
        'total_weeks': total_weeks,
        'weeks_until_event': weeks_until,
        'phase_sequence': sequence,
        'message': message,
    }


def build_remaining_schedule(calendar: dict) -> list[dict]:
    """
    Return one entry per remaining week from today through the event,
    spanning all remaining phases.

    Each entry is `phases.week_entry`: the phase's kind, id, name and
    framework, plus week_in_phase and the absolute week_in_program. It used to
    carry only the kind, so every week to an event ran the goal's default
    framework — Uphill's specific and taper weeks on its base framework.
    """
    sequence = calendar['phase_sequence']
    start_program_week = calendar['week_in_program']

    weeks = []
    cumulative = 0
    for entry in sequence:
        phase_weeks = entry.get('weeks', 1)
        for w in range(1, phase_weeks + 1):
            prog_wk = cumulative + w
            if prog_wk >= start_program_week:
                weeks.append(phases.week_entry(entry, w, prog_wk))
        cumulative += phase_weeks

    return weeks
