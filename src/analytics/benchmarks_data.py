"""The benchmark standards, with nothing dropped.

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
    ('push',      'thruster'):             ('bw_pct',    '×BW',   False, 'Thruster',       'bw_ratio'),
    ('pull',      'deadlift'):             ('bw_pct',    '×BW',   False, 'Deadlift',       'bw_ratio'),
    ('pull',      'power_clean'):          ('bw_pct',    '×BW',   False, 'Power Clean',    'bw_ratio'),
    ('core',      'four_point_ab_bridge'): ('time_min',  ' min',  False, 'Plank Hold',     'time_minutes'),
    ('skill',     'double_under'):         ('reps',      ' reps', False, 'Double-Under',   'reps'),
    ('endurance', 'run_400m'):             ('time',      ' min',  True,  '400m Run',       'time_minutes'),
    ('endurance', 'run_800m'):             ('time',      ' min',  True,  '800m Run',       'time_minutes'),
    ('endurance', 'row_500m'):             ('time',      ' min',  True,  '500m Row',       'time_minutes'),
}
_CELL_LEVELS = [('I', 'entry'), ('II', 'intermediate'), ('III', 'advanced'), ('IV', 'elite')]
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
            'goal_relevance': [], 'sources': ['the_cell'], 'notes': None,
            'test_protocol': None, 'description': None,
        })
    return out


def by_id() -> dict[str, dict]:
    return {b['id']: b for b in load_benchmarks()}


def to_client(b: dict, sex: str = 'male') -> dict:
    """The shape frontend/src/api/types.ts BenchmarkStandard expects, plus the
    fields it never got before (additive, so nothing that reads it breaks)."""
    standards = {lvl: b['levels'][lvl][sex] if b['levels'][lvl].get(sex) is not None
                 else b['levels'][lvl]['male'] for lvl in LEVELS if lvl in b['levels']}
    out = {
        'id': b['id'], 'name': b['name'], 'category': b['category'],
        'unit': b['unit'], 'standards': standards, 'lower_is_better': b['lower_is_better'],
        'domain': b.get('domain'), 'metricType': b.get('metric_type'),
        'sources': b.get('sources', []), 'goalRelevance': b.get('goal_relevance', []),
        'femaleStandards': {lvl: b['levels'][lvl]['female'] for lvl in LEVELS
                            if lvl in b['levels'] and b['levels'][lvl].get('female') is not None},
    }
    if b.get('notes'):
        out['notes'] = b['notes']
    return out


def level_of(b: dict, value: float | None, sex: str = 'male') -> dict:
    """Where a value sits on the ladder.

    {'index': 0-4, 'level': None|entry..elite, 'next': level|None, 'gap': float|None}
    index 0 = below entry. Respects lower_is_better.
    """
    if value is None:
        return {'index': 0, 'level': None, 'next': 'entry', 'gap': None}
    thresholds = [(lvl, b['levels'][lvl].get(sex) if b['levels'][lvl].get(sex) is not None
                   else b['levels'][lvl]['male']) for lvl in LEVELS if lvl in b['levels']]
    better = (lambda v, t: v <= t) if b['lower_is_better'] else (lambda v, t: v >= t)
    reached = None
    idx = 0
    for i, (lvl, t) in enumerate(thresholds, start=1):
        if better(value, t):
            reached, idx = lvl, i
        else:
            break
    nxt = thresholds[idx][0] if idx < len(thresholds) else None
    gap = None
    if nxt is not None:
        t = thresholds[idx][1]
        gap = round((value - t) if b['lower_is_better'] else (t - value), 3)
    return {'index': idx, 'level': reached, 'next': nxt, 'gap': gap}
