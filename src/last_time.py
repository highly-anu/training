"""What the athlete did last time, per exercise, in a few characters.

The watches show it beside today's prescription ("last 24kg × 10") so the
session can be beaten on the wrist. Pure over the session logs; the watch's
today-session sends it with each exercise (`last`, ?spec=1 builds only).
"""
from __future__ import annotations

from datetime import datetime


def _num(v) -> str:
    v = round(float(v), 1)
    return str(int(v)) if v == int(v) else str(v)


def describe(perf: dict) -> str | None:
    """One exercise's logged performance as a short line, or None.

    The heaviest completed set ("24kg × 10"), else the most reps ("12 reps"),
    else the longest hold ("45 s"), else rounds, minutes or kilometres — the
    fields the analytics read, in that order.
    """
    sets = [s for s in perf.get('sets') or [] if s.get('completed')]
    weighted = [s for s in sets if isinstance(s.get('weightKg'), (int, float)) and s['weightKg'] > 0]
    if weighted:
        top = max(weighted, key=lambda s: (s['weightKg'], s.get('repsActual') or 0))
        reps = top.get('repsActual')
        return f"{_num(top['weightKg'])}kg" + (f" × {reps}" if reps else '')
    reps = [s['repsActual'] for s in sets if isinstance(s.get('repsActual'), (int, float)) and s['repsActual'] > 0]
    holds = [s['durationSeconds'] for s in sets
             if isinstance(s.get('durationSeconds'), (int, float)) and s['durationSeconds'] > 0]
    if perf.get('rounds'):
        return f"{_num(perf['rounds'])} rounds"
    if reps and perf.get('durationSec'):
        return f"{_num(max(reps))} reps in {_num(perf['durationSec'] / 60)} min"
    if reps:
        return f"{_num(max(reps))} reps"
    if holds:
        return f"{_num(max(holds))} s"
    if perf.get('distanceKm'):
        return f"{_num(perf['distanceKm'])} km"
    if perf.get('durationSec'):
        return f"{_num(perf['durationSec'] / 60)} min"
    return None


def _local_day(completed_at, tz: str | None) -> str:
    """The athlete's calendar day of a UTC completion time — not its UTC
    date, which runs a day ahead every evening west of Greenwich (a session
    finished yesterday evening read as today's and was skipped)."""
    raw = str(completed_at or '')
    if not tz:
        return raw[:10]
    try:
        from src.fit_import import local_date
        return local_date(datetime.fromisoformat(raw.replace('Z', '+00:00')), tz=tz)
    except (ValueError, TypeError):
        return raw[:10]


def last_by_exercise(session_logs, before: str, tz: str | None = None) -> dict[str, str]:
    """{exercise id: short line} from the most recent completed log before
    `before` (an ISO date, the athlete's) that says something about the
    exercise; `tz` is the profile's IANA zone, so the completion is dated the
    athlete's day.

    `session_logs` is a dict of logs or an iterable of them. The logs are
    client JSON nobody validates, and this runs on the watch's sync: a row
    that cannot be read is skipped, never raised."""
    logs = session_logs.values() if isinstance(session_logs, dict) else (session_logs or [])
    dated = []
    for log in logs:
        if not isinstance(log, dict):
            continue
        at = _local_day(log.get('completedAt'), tz) if log.get('completedAt') else ''
        if at and at < before:
            dated.append((str(log.get('completedAt')), log))
    out: dict[str, str] = {}
    for _, log in sorted(dated, key=lambda t: t[0], reverse=True):
        exercises = log.get('exercises')
        if not isinstance(exercises, dict):
            continue
        for ex_id, perf in exercises.items():
            if ex_id in out or not isinstance(perf, dict):
                continue
            try:
                line = describe(perf)
            except (TypeError, ValueError, AttributeError):
                continue
            if line:
                out[ex_id] = line
    return out
