"""Everything a section or primitive needs to know about the program in hand.

Built once per request from the stored envelope and the athlete's logs, then
handed to every section. The awkward parts of the data live here so nothing
downstream has to re-derive them:

  * the **window** — session logs, matches and workouts are keyed
    program-relatively ("3-Monday-0") and a regenerate leaves the last block's
    rows under the same keys, so every input is filtered to the program's own
    date span before anything counts it;
  * **week → date**, through `workout_matcher.session_calendar_date`, the one
    place that arithmetic lives on the server;
  * the **duration hierarchy** — matched workout, else the log's timeline
    span, else the prescribed minutes, else the archetype estimate (×0.7 on a
    deload week, as the selector scales it);
  * which **framework governs a week**, and which tier a modality sits in.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime, timedelta

from src import loader
from src.analytics.families import family_of
from src.workout_matcher import session_calendar_date
from src.program_keys import DAY_NAMES

DELOAD_PHASES = frozenset({'deload', 'taper'})
DELOAD_DURATION_SCALE = 0.7


@dataclass
class AnalyticsInputs:
    program: dict                                   # currentProgram: goal, constraints, weeks
    start_date: date
    today: date
    session_logs: dict = field(default_factory=dict)      # session_key -> log (health_store shape)
    matches: list = field(default_factory=list)           # [{importedWorkoutId, sessionKey, matchConfidence}]
    workouts: list = field(default_factory=list)          # health_store workout rows
    performance_logs: dict = field(default_factory=dict)  # benchmark_id -> [{value, date}]
    bio_logs: list = field(default_factory=list)
    profile: dict = field(default_factory=dict)
    philosophy_weights: dict = field(default_factory=dict)


class Context:
    def __init__(self, inputs: AnalyticsInputs, *, frameworks: dict | None = None,
                 modalities: dict | None = None, exercises: dict | None = None):
        self.program = inputs.program or {}
        self.goal = self.program.get('goal') or {}
        self.constraints = self.program.get('constraints') or {}
        self.weeks: list[dict] = list(self.program.get('weeks') or [])
        self.start_date = inputs.start_date
        self.today = inputs.today
        self.profile = inputs.profile or {}
        self.philosophy_weights = inputs.philosophy_weights or {}
        self.performance_logs = inputs.performance_logs or {}
        self.bio_logs = inputs.bio_logs or []

        self.frameworks = frameworks if frameworks is not None else loader.load_all_frameworks()
        self.modalities = modalities if modalities is not None else loader.load_all_modalities()
        self._exercises = exercises

        self.end_date = self.start_date + timedelta(days=7 * len(self.weeks))
        self.session_logs = {k: v for k, v in (inputs.session_logs or {}).items()
                             if self._in_window(_log_date(v))}
        self.workouts = {w['id']: w for w in (inputs.workouts or [])
                         if w.get('id') and self._in_window(_parse_date(w.get('date')))}
        self.matches = [m for m in (inputs.matches or [])
                        if m.get('matchConfidence') != 'rejected'
                        and m.get('importedWorkoutId') in self.workouts]
        self._match_by_key: dict[str, dict] = {}
        for m in self.matches:
            self._match_by_key.setdefault(m.get('sessionKey') or '', m)

    # ── dates ────────────────────────────────────────────────────────────────

    def _in_window(self, d: date | None) -> bool:
        return d is None or self.start_date <= d < self.end_date

    def week_start(self, week_index: int) -> date:
        return self.start_date + timedelta(days=7 * week_index)

    def session_date(self, week_index: int, day: str) -> date | None:
        iso = session_calendar_date(self.start_date.isoformat(), week_index, day)
        return date.fromisoformat(iso) if iso else None

    def is_elapsed(self, week_index: int, day: str) -> bool:
        d = self.session_date(week_index, day)
        return d is not None and d <= self.today

    @property
    def elapsed_week_indexes(self) -> list[int]:
        return [i for i in range(len(self.weeks)) if self.week_start(i) <= self.today]

    @property
    def current_week_index(self) -> int | None:
        if self.today < self.start_date:
            return None
        idx = (self.today - self.start_date).days // 7
        return idx if idx < len(self.weeks) else None

    # ── weeks and frameworks ────────────────────────────────────────────────

    def framework_for_week(self, week: dict) -> dict | None:
        fw = week.get('framework')
        fw_id = fw.get('id') if isinstance(fw, dict) else fw
        if fw_id and fw_id in self.frameworks:
            return self.frameworks[fw_id]
        default = (self.goal.get('framework_selection') or {}).get('default_framework')
        return self.frameworks.get(default) if default else None

    def is_deload_week(self, week: dict) -> bool:
        return bool(week.get('is_deload')) or (week.get('phase') in DELOAD_PHASES)

    def tier_of(self, modality: str, week: dict) -> str:
        fw = self.framework_for_week(week) or {}
        tiers = fw.get('modality_priority') or {}
        for tier in ('committed', 'core', 'supplementary'):
            if modality in (tiers.get(tier) or []):
                return tier
        return 'unscheduled' if not (fw.get('sessions_per_week') or {}).get(modality) else 'core'

    def modality_def(self, modality: str) -> dict:
        return self.modalities.get(modality) or {}

    def exercise_def(self, exercise_id: str) -> dict:
        if self._exercises is None:
            self._exercises, _ = loader.load_all_exercises()
        return self._exercises.get(exercise_id) or {}

    # ── sessions, logs, matches ─────────────────────────────────────────────

    def sessions(self, *, elapsed_only: bool = True):
        """Yield {week, week_index, day, session_index, session, date} in schedule order."""
        for week_index, week in enumerate(self.weeks):
            for day in DAY_NAMES:
                for session_index, session in enumerate((week.get('schedule') or {}).get(day) or []):
                    d = self.session_date(week_index, day)
                    if elapsed_only and (d is None or d > self.today):
                        continue
                    yield {'week': week, 'week_index': week_index, 'day': day,
                           'session_index': session_index, 'session': session, 'date': d}

    def session_keys(self, week: dict, day: str, session_index: int, week_index: int) -> list[str]:
        """Indexed key first, then the day-level key every older writer used."""
        week_number = week.get('week_number', week_index + 1)
        return [f'{week_number}-{day}-{session_index}', f'{week_number}-{day}']

    def log_for(self, hit: dict) -> dict | None:
        """The session log for a session; a day-level log only when it is unambiguous."""
        keys = self.session_keys(hit['week'], hit['day'], hit['session_index'], hit['week_index'])
        log = self.session_logs.get(keys[0])
        if log is not None:
            return log
        sessions_that_day = (hit['week'].get('schedule') or {}).get(hit['day']) or []
        if len(sessions_that_day) == 1:
            return self.session_logs.get(keys[1])
        return None

    def completed(self, hit: dict) -> bool:
        log = self.log_for(hit)
        return bool(log and log.get('completedAt'))

    def workout_for(self, hit: dict) -> dict | None:
        keys = self.session_keys(hit['week'], hit['day'], hit['session_index'], hit['week_index'])
        for key in keys:
            m = self._match_by_key.get(key)
            if m:
                return self.workouts.get(m['importedWorkoutId'])
        return None

    def duration_minutes(self, hit: dict) -> tuple[float, str]:
        """(minutes, source) — source ∈ workout | timeline | prescribed | estimate."""
        w = self.workout_for(hit)
        if w and w.get('durationMinutes'):
            return float(w['durationMinutes']), 'workout'
        log = self.log_for(hit)
        span = _timeline_span_minutes(log)
        if span:
            return span, 'timeline'
        session = hit['session']
        prescribed = sum(
            float((ea.get('load') or {}).get('duration_minutes') or 0)
            for ea in (session.get('exercises') or [])
            if not (ea.get('meta') or ea.get('injury_skip') or ea.get('coverage_gap')))
        if prescribed > 0:
            return prescribed, 'prescribed'
        est = float((session.get('archetype') or {}).get('duration_estimate_minutes') or 0)
        if self.is_deload_week(hit['week']):
            est *= DELOAD_DURATION_SCALE
        return est, 'estimate'

    def family(self, modality: str | None) -> str:
        return family_of(modality)


# ── helpers ──────────────────────────────────────────────────────────────────

def _parse_date(value) -> date | None:
    if value is None:
        return None
    if isinstance(value, date):
        return value
    try:
        return date.fromisoformat(str(value)[:10])
    except ValueError:
        return None


def _log_date(log: dict) -> date | None:
    return _parse_date((log or {}).get('completedAt') or None)


def _timeline_span_minutes(log: dict | None) -> float | None:
    if not log:
        return None
    ends: list[float] = []
    starts: list[float] = []
    for entry in log.get('exerciseTimeline') or []:
        if entry.get('startOffset') is not None:
            starts.append(float(entry['startOffset']))
        if entry.get('endOffset') is not None:
            ends.append(float(entry['endOffset']))
    for ex in (log.get('exercises') or {}).values():
        for s in (ex or {}).get('sets') or []:
            if s.get('startOffset') is not None:
                starts.append(float(s['startOffset']))
            if s.get('endOffset') is not None:
                ends.append(float(s['endOffset']))
    if starts and ends and max(ends) > min(starts):
        return (max(ends) - min(starts)) / 60.0
    return None


def parse_iso_date(value) -> date | None:
    """Public alias for the API layer."""
    return _parse_date(value)
