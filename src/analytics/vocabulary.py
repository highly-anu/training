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
    # Analytics ▸ Program's Scorecard and Intensity split (src/analytics/scorecard.py,
    # intensity.py, hr_plan.py).
    'completion': {'label': 'Completion',
                   'text': 'Sessions done of those due so far, per modality; one counts as done when it is '
                           'logged or a workout is matched to it. The framework ranks each modality '
                           'committed, core or supplementary, and the headline is a gate, not an average: '
                           'under 70 % of the committed sessions is off plan, however the rest went.'},
    'weekly_dose': {'label': 'Minutes a week',
                    'text': 'Minutes done per elapsed week against the plan\'s, and against the modality\'s '
                            'own weekly range: under, in range or over.'},
    'intensity': {'label': 'Intensity split',
                  'text': 'How the completed sessions\' minutes fall across heart-rate zones, against what '
                          'their programming planned. Heart rate counts only where an exercise prescribes a '
                          'zone, such as an easy run or a zoned warm-up; work that prescribes a load or an '
                          'effort counts as max effort, strap or not.'},
    'hr_zones': {'label': 'Heart-rate zones',
                 'text': 'Shares of your maximum heart rate: zone 1 under 65 %, zone 2 to 78 % (near the '
                         'aerobic threshold), zone 3 to 87 %, zone 4 to 93 %, zone 5 above.'},
    # Analytics ▸ Load (src/analytics/load_summary.py) and ▸ Blocks (development.py).
    'load_focus': {'label': 'Load focus',
                   'text': 'The last 28 days of recorded heart rate in three bands: base is zones 1–2, '
                           'threshold zone 3, anaerobic zones 4–5. Workouts without heart rate are left out.'},
    'mix': {'label': 'Mix',
            'text': 'The period\'s recorded minutes by modality, the kind of training a workout was filed '
                    'as, and by activity, as the watch or app named it.'},
    'consistency': {'label': 'Sessions a week',
                    'text': 'Workouts recorded in each of the last 12 weeks, Monday to Sunday, of any kind, '
                            'planned or not.'},
    'block_load': {'label': 'Load by block',
                   'text': 'Each week\'s TRIMP in the colour of the block in force that week. A block\'s '
                           'average is its TRIMP over its weeks in the window, weeks without a workout '
                           'included.'},
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
