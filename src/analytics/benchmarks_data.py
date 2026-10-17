"""The standards, with nothing dropped.

(The files, ids and keys still say "benchmark" — `benchmark_id`, `/api/benchmarks`
— because they are stored and on the wire; everything a person reads says
"standard", a logged value is a "result".)

api._all_benchmarks flattened data/benchmarks into a client shape and lost, on
the way, the one authored link from a standard to a goal: `sources` (which
philosophies a standard belongs to), `goal_relevance`, `domain`, `metric_type`
and every female value. Analytics needs all of them to say "these are the
standards *this* program is measured by". This loader keeps everything and
offers `to_client` for the legacy shape, so the endpoint can delegate here.
"""
from __future__ import annotations

import os
from functools import lru_cache

import yaml

_DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'data')
LEVELS = ('entry', 'intermediate', 'advanced', 'elite')

CATEGORY_OF_DOMAIN = {
    'max_strength': 'strength', 'power': 'strength', 'relative_strength': 'strength',
    'strength_endurance': 'conditioning', 'aerobic_base': 'conditioning',
    'anaerobic_intervals': 'conditioning',
}
# One set of group names, in one order, for every screen that lists standards.
# Web Profile, Explore and iOS each used to word and order these themselves.
CATEGORIES = (
    ('strength', 'Strength'),
    ('conditioning', 'Conditioning'),
    ('kettlebell', 'Kettlebell pentathlon'),
    ('tactical', 'Ruck & PT tests'),
    ('benchmark_wod', 'Benchmark workouts'),
    ('skill', 'Movement & skill'),
    ('cell', 'The Cell'),
)
CATEGORY_NAME = dict(CATEGORIES)
CATEGORY_ORDER = {c: i for i, (c, _) in enumerate(CATEGORIES)}

# Bodyweight is stored as a standard's series (`bodyweight_kg`) so a ×BW ratio
# can be read against the weight on that day; it is a valid result id without
# being a standard.
BODYWEIGHT_ID = 'bodyweight_kg'

UNIT_OF_METRIC = {'bw_ratio': '×BW', 'reps': ' reps', 'time_minutes': ' min',
                  'metres': ' m', 'time_sec': ' s', 'time_seconds': ' s', 'kg': ' kg',
                  'score': ''}

# The list-of-entries files under data/benchmarks. A file may set `category`
# per entry (kettlebell, tactical, benchmark_wod, skill) where the domain's
# default grouping would be misleading, and `unit` where the metric's default
# unit is not the one the standard is read in.
BENCHMARK_FILES = (
    'strength_standards.yaml',
    'conditioning_standards.yaml',
    'kettlebell_pentathlon.yaml',
    'ruck_and_pt_standards.yaml',
    'crossfit_benchmark_wods.yaml',
    'movement_skill_standards.yaml',
)

# (domain, exercise_key) -> (value_key, unit, lower_is_better, display_name, metric_type)
_CELL_EXTRACT = {
    ('hips',      'back_squat'):           ('bw_pct',    '×BW',   False, 'Back Squat',     'bw_ratio'),
    ('hips',      'broad_jump'):           ('metres',    ' m',    False, 'Broad Jump',     'metres'),
    ('push',      'shoulder_press'):       ('bw_pct',    '×BW',   False, 'Shoulder Press', 'bw_ratio'),
    ('pull',      'deadlift'):             ('bw_pct',    '×BW',   False, 'Deadlift',       'bw_ratio'),
    ('pull',      'power_clean'):          ('bw_pct',    '×BW',   False, 'Power Clean',    'bw_ratio'),
    ('work_capacity', 'thruster'):         ('bw_pct',    '×BW',   False, 'Thruster',       'bw_ratio'),
    ('core',      'four_point_ab_bridge'): ('time_min',  ' min',  False, 'Plank Hold',     'time_minutes'),
    ('skill',     'double_under'):         ('reps',      ' reps', False, 'Double-Under',   'reps'),
    ('endurance', 'run_400m'):             ('time',      ' min',  True,  '400m Run',       'time_minutes'),
    ('endurance', 'run_800m'):             ('time',      ' min',  True,  '800m Run',       'time_minutes'),
    ('endurance', 'row_500m'):             ('time',      ' min',  True,  '500m Row',       'time_minutes'),
}
# The Cell has five levels and names them: I basic, II beginner, III
# intermediate, IV advanced, V elite. Its own words decide the mapping, so the
# app's elite is Cell V (it used to be IV, which Cell calls "Advanced") and
# Cell I sits below entry.
_CELL_LEVELS = [('II', 'entry'), ('III', 'intermediate'), ('IV', 'advanced'), ('V', 'elite')]
# Standards whose threshold is a load for a number of reps.
_CELL_NOTES = {('work_capacity', 'thruster'): 'Load as ×BW for 21 reps (30 reps at elite).'}
_CELL_DOMAIN_MODALITY = {'hips': 'max_strength', 'push': 'max_strength', 'pull': 'max_strength',
                         'core': 'durability', 'skill': 'movement_skill',
                         'endurance': 'anaerobic_intervals', 'work_capacity': 'strength_endurance'}


def _load_yaml(path: str):
    with open(path, encoding='utf-8') as f:
        return yaml.safe_load(f)


def parse_time(t) -> float:
    """'M:SS' → minutes as float; numbers pass through."""
    if isinstance(t, (int, float)):
        return float(t)
    parts = str(t).split(':')
    return round(int(parts[0]) + int(parts[1]) / 60, 3)


@lru_cache(maxsize=1)
def load_benchmarks() -> tuple:
    out: list[dict] = []
    for fname in BENCHMARK_FILES:
        path = os.path.join(_DATA_DIR, 'benchmarks', fname)
        if not os.path.exists(path):
            continue
        for item in _load_yaml(path) or []:
            levels = item.get('levels') or {}
            norm = {}
            for lvl in LEVELS:
                d = levels.get(lvl)
                if not isinstance(d, dict) or d.get('male') is None:
                    continue
                norm[lvl] = {'male': float(d['male']),
                             'female': float(d['female']) if d.get('female') is not None else None,
                             'note': (d.get('note') or '').strip() or None}
            if len(norm) < 4:
                continue
            metric = item.get('metric_type', '')
            out.append({
                'id': item['id'], 'name': item['name'],
                'category': item.get('category') or CATEGORY_OF_DOMAIN.get(item.get('domain', ''), 'conditioning'),
                'domain': item.get('domain'), 'metric_type': metric,
                'unit': item.get('unit') if item.get('unit') is not None else UNIT_OF_METRIC.get(metric, ''),
                'lower_is_better': bool(item.get('lower_is_better', False)),
                'levels': norm,
                'goal_relevance': list(item.get('goal_relevance') or []),
                'sources': list(item.get('sources') or []),
                'notes': (item.get('notes') or '').strip() or None,
                'test_protocol': (item.get('test_protocol') or '').strip() or None,
                'description': (item.get('description') or '').strip() or None,
                # Training that estimates it (est. 1RM ÷ bodyweight that day).
                'derived_from': item.get('derived_from'),
                # A distance an imported run's fastest window reads as.
                'best_effort': item.get('best_effort'),
            })
    out.extend(_cell_benchmarks())
    return tuple(out)


def _cell_benchmarks() -> list[dict]:
    path = os.path.join(_DATA_DIR, 'benchmarks', 'cell_standards.yaml')
    if not os.path.exists(path):
        return []
    standards = (_load_yaml(path) or {}).get('standards') or {}
    out = []
    for (domain, exercise), (key, unit, lower, name, metric) in _CELL_EXTRACT.items():
        levels_data = (standards.get(domain) or {}).get(exercise, {}).get('levels') or {}
        norm = {}
        for roman, lvl in _CELL_LEVELS:
            d = levels_data.get(roman) or {}
            if key == 'bw_pct':
                m, f = d.get('male_bw_pct'), d.get('female_bw_pct')
            elif key == 'time':
                m, f = d.get('male_time'), d.get('female_time')
            else:
                m, f = d.get(key), d.get(key)
            if m is None:
                break
            conv = parse_time if key in ('time', 'time_min') else float
            norm[lvl] = {'male': conv(m), 'female': conv(f) if f is not None else None, 'note': None}
        if len(norm) < 4:
            continue
        out.append({
            'id': f'cell_{domain}_{exercise}', 'name': name, 'category': 'cell',
            'domain': _CELL_DOMAIN_MODALITY.get(domain, domain), 'metric_type': metric,
            'unit': unit, 'lower_is_better': lower, 'levels': norm,
            'goal_relevance': [], 'sources': ['the_cell'], 'notes': _CELL_NOTES.get((domain, exercise)),
            'test_protocol': None, 'description': None,
        })
    return out


def by_id() -> dict[str, dict]:
    return {b['id']: b for b in load_benchmarks()}


def known_ids() -> set[str]:
    """Every id a result may be stored under: the standards plus bodyweight."""
    return {b['id'] for b in load_benchmarks()} | {BODYWEIGHT_ID}


def thresholds(b: dict, sex: str = 'male') -> dict[str, float]:
    """{level: value} for one sex, the male value standing in where a table
    has none. (`levels[lvl].get(sex, male)` is wrong: the key exists with None.)"""
    return {lvl: b['levels'][lvl][sex] if b['levels'][lvl].get(sex) is not None
            else b['levels'][lvl]['male'] for lvl in LEVELS if lvl in b['levels']}


def number_text(v: float, places: int = 2) -> str:
    """A number without trailing noughts: 1.5, 2, 82.4."""
    text = f'{v:.{places}f}'
    if '.' in text:
        text = text.rstrip('0').rstrip('.')
    return '0' if text == '-0' else text


def _clock(total_seconds: float) -> str:
    secs = int(round(total_seconds))
    h, rem = divmod(secs, 3600)
    m, s = divmod(rem, 60)
    return f'{h}:{m:02d}:{s:02d}' if h else f'{m}:{s:02d}'


def format_value(b: dict | None, value: float | None) -> str | None:
    """A value as every screen and both watches print it: 4:58, 1.62×BW, 45 reps.

    Times are clocks (a Fran of 4.97 min is "4:58", a 12-mile ruck "3:20:00");
    seconds stay seconds (a handstand of "45 s"); everything else is the number
    with the standard's unit. `b` None formats bodyweight.
    """
    if value is None:
        return None
    if b is None:
        return f'{number_text(value, 1)} kg'
    metric = b.get('metric_type')
    if metric == 'time_minutes':
        return _clock(value * 60)
    if metric in ('time_seconds', 'time_sec'):
        return f'{number_text(value, 1)} s'
    text, unit = (number_text(value, 0), b.get('unit') or ' reps') if metric == 'reps' else (number_text(value), b.get('unit') or '')
    if text == '1' and unit in (' reps', ' rounds'):
        unit = unit[:-1]
    return f'{text}{unit}'


def parse_input(b: dict | None, text) -> float | None:
    """What an athlete typed, in the standard's unit: "4:58" or "1:12:30" for a
    time, "1:30" or "90" for a hold, a plain number for the rest. None when it
    is not a value. The inverse of `format_value`, so a field can show a result
    the way it will be printed and take it back the same way."""
    if isinstance(text, bool) or text is None:
        return None
    if isinstance(text, (int, float)):
        value = float(text)
    else:
        raw = str(text).strip().replace(',', '.')
        # A value as it is printed reads back: "1.62×BW", "45 reps", "90 s".
        for suffix in sorted({(b or {}).get('unit', '').strip(), '×BW', 'xBW', 'reps', 'rep', 'rounds',
                              'round', 'kg', 's', 'm'} - {''}, key=len, reverse=True):
            if raw.lower().endswith(suffix.lower()):
                raw = raw[:-len(suffix)].strip()
                break
        metric = (b or {}).get('metric_type')
        if ':' in raw and metric in ('time_minutes', 'time_seconds', 'time_sec'):
            try:
                parts = [float(p) for p in raw.split(':')]
            except ValueError:
                return None
            if len(parts) > 3 or any(p < 0 for p in parts) or any(p >= 60 for p in parts[1:]):
                return None
            seconds = 0.0
            for p in parts:
                seconds = seconds * 60 + p
            value = seconds / 60 if metric == 'time_minutes' else seconds
        else:
            try:
                value = float(raw)
            except ValueError:
                return None
    if value != value or value in (float('inf'), float('-inf')) or value < 0:
        return None
    # Nought pull-ups is a result (below entry); a nought time or load is a typo.
    if value == 0 and (b or {}).get('metric_type') not in ('reps', 'score'):
        return None
    return round(value, 4)


def input_hint(b: dict) -> str:
    """The placeholder a result field shows: the shape `parse_input` reads."""
    metric = b.get('metric_type')
    if metric == 'time_minutes':
        return 'h:mm:ss' if max(lv['male'] for lv in b['levels'].values()) >= 60 else 'm:ss'
    if metric in ('time_seconds', 'time_sec'):
        return 'seconds'
    return (b.get('unit') or '').strip() or 'value'


def to_client(b: dict, sex: str = 'male') -> dict:
    """The shape frontend/src/api/types.ts BenchmarkStandard expects, plus the
    fields it never got before (additive, so nothing that reads it breaks)."""
    standards = thresholds(b, sex)
    out = {
        'id': b['id'], 'name': b['name'], 'category': b['category'],
        'categoryName': CATEGORY_NAME.get(b['category'], b['category']),
        'categoryOrder': CATEGORY_ORDER.get(b['category'], len(CATEGORIES)),
        'unit': b['unit'], 'standards': standards, 'lower_is_better': b['lower_is_better'],
        'standardsText': {lvl: format_value(b, v) for lvl, v in standards.items()},
        'inputHint': input_hint(b),
        'domain': b.get('domain'), 'metricType': b.get('metric_type'),
        'sources': b.get('sources', []), 'goalRelevance': b.get('goal_relevance', []),
        'femaleStandards': {lvl: b['levels'][lvl]['female'] for lvl in LEVELS
                            if lvl in b['levels'] and b['levels'][lvl].get('female') is not None},
    }
    if b.get('notes'):
        out['notes'] = b['notes']
    if b.get('test_protocol'):
        out['testProtocol'] = b['test_protocol']
    if b.get('description'):
        out['description'] = b['description']
    if b.get('best_effort'):
        # The Standard detail says imported runs can suggest a result here.
        out['bestEffort'] = {'km': b['best_effort']['km'], 'label': b['best_effort']['label']}
    return out


def level_of(b: dict, value: float | None, sex: str = 'male') -> dict:
    """Where a value sits on the ladder.

    {'index': 0-4, 'level': None|entry..elite, 'next': level|None, 'gap': float|None}
    index 0 = below entry. Respects lower_is_better.
    """
    if value is None:
        return {'index': 0, 'level': None, 'next': 'entry', 'gap': None}
    thresholds_ = list(thresholds(b, sex).items())
    better = (lambda v, t: v <= t) if b['lower_is_better'] else (lambda v, t: v >= t)
    reached = None
    idx = 0
    for i, (lvl, t) in enumerate(thresholds_, start=1):
        if better(value, t):
            reached, idx = lvl, i
        else:
            break
    nxt = thresholds_[idx][0] if idx < len(thresholds_) else None
    gap = None
    if nxt is not None:
        t = thresholds_[idx][1]
        gap = round((value - t) if b['lower_is_better'] else (t - value), 3)
    return {'index': idx, 'level': reached, 'next': nxt, 'gap': gap}
