"""Reading a stored program regardless of which client wrote it.

Programs in `user_programs` have been written by the web app (camelCase at the
top level, snake_case inside) and by older iOS builds (snake_case at the top
level, sometimes camelCase inside). These two helpers absorb that so callers
don't each reinvent the tolerance.

Kept in its own module rather than in api.py so `src/` code — the workout
matcher in particular — can use it without importing api.py, which would be a
circular import.
"""
from __future__ import annotations

DAY_NAMES = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']

_TOP_LEVEL_KEY_MAP = {
    'current_program':     'currentProgram',
    'program_start_date':  'programStartDate',
    'event_date':          'eventDate',
    'source_goal_ids':     'sourceGoalIds',
    'source_goal_weights': 'sourceGoalWeights',
}


def normalize_program_keys(program: dict) -> dict:
    """Remap legacy snake_case top-level program keys to camelCase.

    Old iOS clients saved with snake_case CodingKeys, corrupting the stored
    payload. Both web (reads .currentProgram) and iOS (no CodingKeys on
    ServerProgram → expects camelCase) fail silently without this fix.
    """
    return {_TOP_LEVEL_KEY_MAP.get(k, k): v for k, v in program.items()}


def pick(d: dict, *keys):
    """First present value among snake_case / camelCase spellings."""
    for k in keys:
        if isinstance(d, dict) and d.get(k) is not None:
            return d[k]
    return None
