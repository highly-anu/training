"""Whether a stored match or session log belongs to the program in force now.

A session's legacy key ('6-Monday-0') is program-relative: every plan the
athlete has ever had has a week 6 Monday. `session_uid` pins a row to one
program version, but rows written before program history existed, or whose
key could not be resolved on their date, carry no uid — and every reader used
to assume such a row was the current program's "rather than hide real data".
That is how a March workout and its April log showed up on a program started
in October as week 6, linked and completed, weeks before week 6 began.

So a key is never enough. A row belongs to the active program only if its
dates agree with the session it names *in that program*:

  * a match's workout must fall within a day of the session's planned date
    (the slack covers a UTC-dated evening workout, as resolve_session's
    `widen` does);
  * a log's completion must not come before the session's week — up to six
    days early is a rearranged week, more is a different program.

A row with a uid from another version never belongs. A row with no date to
check (a log never marked complete, a match whose workout is gone) and no uid
cannot be placed, so it does not belong either. The rows themselves are never
touched: history readers (`get_session_logs_by_uid`, Program History, the
development document) still see all of them.

Pure — `planned` is what `program_history.active_plan_dates` returns.
"""
from __future__ import annotations

from datetime import date, datetime, timedelta

MATCH_SLACK_DAYS = 1
LOG_EARLY_DAYS = 6


def _as_date(value) -> date | None:
    if value is None or value == '':
        return None
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    try:
        return date.fromisoformat(str(value)[:10])
    except ValueError:
        return None


def planned_date(planned: dict[str, date], key: str | None) -> date | None:
    """The active program's date for a legacy key, in either shape in the wild:
    '{week}-{Day}-{index}' exactly, or a day-level '{week}-{Day}', whose
    sessions all fall on one date (see program_history._by_legacy_key)."""
    if not key:
        return None
    if key in planned:
        return planned[key]
    if key.count('-') >= 2:
        return None
    days = {d for k, d in planned.items() if k.startswith(key + '-')}
    return days.pop() if len(days) == 1 else None


def _uid_ok(uid: str | None, active_vid: str | None) -> bool | None:
    """False for another version's uid, True for ours, None when unscoped."""
    if not uid:
        return None
    return uid.startswith(active_vid + ':')


def match_in_active(match: dict, workout_date, active_vid: str | None,
                    planned: dict[str, date]) -> bool:
    """`match` as get_matches returns it; `workout_date` the matched workout's."""
    if not active_vid:
        return True                       # no history (local dev): as before
    scoped = _uid_ok(match.get('sessionUid'), active_vid)
    if scoped is not None:
        return scoped                     # resolved on the workout's own date
    when = planned_date(planned, match.get('sessionKey'))
    got = _as_date(workout_date)
    if when is None or got is None:
        return False
    return abs((got - when).days) <= MATCH_SLACK_DAYS


def log_in_active(uid: str | None, key: str | None, completed_at,
                  active_vid: str | None, planned: dict[str, date]) -> bool:
    """A session log row: its uid, legacy key and completion timestamp."""
    if not active_vid:
        return True
    scoped = _uid_ok(uid, active_vid)
    if scoped is False:
        return False
    done = _as_date(completed_at)
    if scoped and done is None:
        return True                       # this program's sets, not yet completed
    when = planned_date(planned, key)
    if when is None or done is None:
        return False
    # Stamped by key alone (program_history.active_session_uid), so a stale
    # client's "week 6 Monday" lands on this program's week 6 — the date is
    # what tells it apart.
    return done >= when - timedelta(days=LOG_EARLY_DAYS)
