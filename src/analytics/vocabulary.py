"""The engine's twelve primitives, in words.

What each one measures, in what unit, what has to be logged for it to measure
anything, and where that is captured. This is the one place the words live —
the Explore tab reads them to say what a philosophy tracks before a single
session exists, and the coverage reason codes in the primitives are the
*failure* words for the same fields. `test_program_analytics.py` asserts every
primitive in `spec.PRIMITIVES` has an entry.

`needs` names capture requirements by a stable field id so a client can
de-duplicate them across entries: two entries that both need `sets` are one
thing to log, not two.
"""
from __future__ import annotations

# field id -> (label, where it is captured)
NEEDS: dict[str, dict] = {
    'sets':       {'label': 'Reps and kg per set',
                   'where': 'Session logger on the web, or the watch'},
    'rpe':        {'label': 'RPE on each set',
                   'where': 'Session logger (RPE field)'},
    'rpe_target': {'label': 'A prescribed RPE on the slot',
                   'where': 'The program itself — only frameworks that prescribe RPE'},
    'rounds':     {'label': 'Rounds (and reps) in the time cap',
                   'where': 'Outcome logger on AMRAP and EMOM sessions'},
    'minutes':    {'label': 'Session minutes',
                   'where': 'A matched workout, or the outcome logger'},
    'km':         {'label': 'Distance in km',
                   'where': 'A matched workout, or the outcome logger'},
    'hold':       {'label': 'Hold seconds per set',
                   'where': 'The watch records them; on the web, the outcome logger'},
    'timed_reps': {'label': 'Reps and seconds on the same set',
                   'where': 'Session logger with set timing, or the watch'},
    'hr':         {'label': 'Heart-rate samples',
                   'where': 'A matched workout from a watch, Strava or Garmin'},
    'gps_hr':     {'label': 'GPS track and heart rate on a run or ride',
                   'where': 'A matched workout with both'},
    'completion': {'label': 'Sessions marked complete',
                   'where': 'The session check-off'},
    'prs':        {'label': 'PRs on the standards (and bodyweight for ×BW ratios)',
                   'where': 'Profile → Benchmarks'},
}

PRIMITIVES: dict[str, dict] = {
    'set_load': {
        'label': 'Set load',
        'measures': 'Best working set and estimated 1RM per session',
        'unit': 'kg',
        'needs': ['sets'],
        'expectedKinds': ['prescribed', 'achieved_plus_increment'],
    },
    'load_at_rpe': {
        'label': 'Load at RPE',
        'measures': 'The load lifted at the prescribed RPE (sets within ±1)',
        'unit': 'kg',
        'needs': ['sets', 'rpe', 'rpe_target'],
        'expectedKinds': ['prescribed'],
    },
    'rounds': {
        'label': 'Rounds',
        'measures': 'Rounds completed in the fixed time',
        'unit': 'rounds',
        'needs': ['rounds', 'completion'],
        'expectedKinds': ['load_field', 'constant'],
    },
    'duration': {
        'label': 'Duration',
        'measures': 'Minutes per session and per week',
        'unit': 'min',
        'needs': ['minutes', 'completion'],
        'expectedKinds': ['load_field', 'constant'],
    },
    'distance': {
        'label': 'Distance',
        'measures': 'Kilometres per session and per week',
        'unit': 'km',
        'needs': ['km', 'completion'],
        'expectedKinds': ['load_field', 'constant'],
    },
    'hold_seconds': {
        'label': 'Hold time',
        'measures': 'Seconds held per set — a proxy for range, which is not captured',
        'unit': 's',
        'needs': ['hold'],
        'expectedKinds': ['load_field', 'constant'],
    },
    'rate': {
        'label': 'Cadence',
        'measures': 'Reps per minute on a timed set',
        'unit': 'rpm',
        'needs': ['timed_reps'],
        'expectedKinds': ['constant'],
    },
    'zone_minutes': {
        'label': 'Intensity split',
        'measures': 'Minutes in each heart-rate zone against the framework\'s split',
        'unit': 'min',
        'needs': ['hr'],
        'expectedKinds': ['framework_field'],
    },
    'aerobic_efficiency': {
        'label': 'Aerobic efficiency',
        'measures': 'Pace-to-heart-rate decoupling within a session, and its trend',
        'unit': '%',
        'needs': ['gps_hr'],
        'expectedKinds': ['none'],
    },
    'unlocks': {
        'label': 'Movements earned',
        'measures': 'Movements practised enough to count, and what they unlock next',
        'unit': 'movements',
        'needs': ['completion'],
        'expectedKinds': ['none'],
    },
    'benchmark_level': {
        'label': 'Standard reached',
        'measures': 'Level reached on named standards, and the gap to the target level',
        'unit': 'level',
        'needs': ['prs'],
        'expectedKinds': ['none'],
    },
    'session_completion': {
        'label': 'Attendance',
        'measures': 'Sessions completed against sessions planned',
        'unit': '%',
        'needs': ['completion'],
        'expectedKinds': ['none'],
    },
}


def to_client() -> dict:
    return {'primitives': PRIMITIVES, 'needs': NEEDS}
