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
                   'where': 'The session logger on the web or the phone, or the watch'},
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
    'prs':        {'label': 'Results on the standards (and bodyweight for ×BW ratios)',
                   'where': 'Profile → Standards'},
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


# The load and recovery readings in words: what each number on Analytics ▸
# Load and ▸ Recovery is, for the About section of its detail screen on either
# client (GET /api/analytics/vocabulary). One or two sentences each; the
# numbers are the server's, so are the words that explain them.
TERMS: dict[str, dict] = {
    'readiness': {'label': 'Readiness',
                  'text': 'A morning score out of 100 from resting heart rate, heart-rate variability '
                          '(or the watch\'s Body Battery and recovery time when there is none), last '
                          'night\'s sleep, how hard recent sessions felt and training load. 70 and above '
                          'is green, 45 to 69 yellow, under 45 red; recovery time still left caps it.'},
    'hrv': {'label': 'Heart-rate variability',
            'text': 'The variation between heartbeats at rest, in milliseconds. Above your own usual '
                    'means better rested; the line is the 7-day average.'},
    'resting_hr': {'label': 'Resting heart rate',
                   'text': 'Your heart rate at rest — the watch\'s overnight low, or Apple Health\'s '
                           'resting heart rate. Below your own usual means better recovered; the line '
                           'is the 7-day average.'},
    'sleep_debt': {'label': 'Sleep debt',
                   'text': 'The hours short of 8 a night over the last 7 nights with sleep recorded.'},
    'trimp': {'label': 'TRIMP',
              'text': 'Training impulse: each minute of a workout weighted by how hard the heart worked '
                      'in it, so a long easy session and a short hard one can score the same.'},
    'ctl': {'label': 'CTL · fitness',
            'text': 'Chronic training load: daily TRIMP averaged over about six weeks (42-day '
                    'exponential). It rises slowly with consistent training.'},
    'atl': {'label': 'ATL · fatigue',
            'text': 'Acute training load: daily TRIMP averaged over about a week (7-day exponential). '
                    'It rises fast after hard days and falls fast with rest.'},
    'tsb': {'label': 'TSB · form',
            'text': 'Training stress balance: yesterday\'s fitness minus fatigue. Negative while a block '
                    'is loading, which is expected; it should climb toward zero and above in a taper.'},
}


def about(primitive: str, notes: str = '') -> dict:
    """One measure in words, for the About section of its detail screen on
    either client: what it measures, what has to be logged for it and where,
    and the package's own note when it wrote one. Built here so the web and the
    phone cannot word one measure two ways."""
    prim = PRIMITIVES.get(primitive) or {}
    return {
        'measures': prim.get('measures'),
        'needs': [{'label': NEEDS[n]['label'], 'where': NEEDS[n]['where']}
                  for n in prim.get('needs') or [] if n in NEEDS],
        'notes': notes or None,
    }


def to_client() -> dict:
    return {'primitives': PRIMITIVES, 'needs': NEEDS, 'terms': TERMS}
