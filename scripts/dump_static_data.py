#!/usr/bin/env python3
"""Dump static YAML reference data to JSON for frontend bundling.

Run from the repo root before `npm run build`:
    python scripts/dump_static_data.py

Output goes to frontend/src/data/static/*.json.
These files are imported directly by TanStack Query hooks, eliminating
API calls for data that never changes at runtime.
"""
from __future__ import annotations

import glob
import json
import math
import os
import sys

# Make src/ importable when run from repo root
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import yaml

_DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'data')
_OUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    'frontend', 'src', 'data', 'static'
)


def _load_yaml(path: str) -> dict | list:
    with open(path, encoding='utf-8') as f:
        return yaml.safe_load(f)


def _all_goals() -> list[dict]:
    goals = []
    for path in sorted(glob.glob(os.path.join(_DATA_DIR, 'goals', '*.yaml'))):
        goals.append(_load_yaml(path))
    return goals


def _all_exercises() -> list[dict]:
    result = []
    for path in sorted(glob.glob(os.path.join(_DATA_DIR, 'exercises', '*.yaml'))):
        data = _load_yaml(path)
        for ex in data.get('exercises', []):
            if isinstance(ex.get('sources'), str):
                ex['sources'] = [ex['sources']]
            result.append(ex)
    return result


def _all_modalities() -> list[dict]:
    result = []
    for path in sorted(glob.glob(os.path.join(_DATA_DIR, 'modalities', '*.yaml'))):
        result.append(_load_yaml(path))
    return result


def _all_frameworks() -> list[dict]:
    result = []
    for path in sorted(glob.glob(os.path.join(_DATA_DIR, 'frameworks', '*.yaml'))):
        result.append(_load_yaml(path))
    return result


def _all_philosophies() -> list[dict]:
    result = []
    for path in sorted(glob.glob(os.path.join(_DATA_DIR, 'philosophies', '*.yaml'))):
        result.append(_load_yaml(path))
    return result


def _equipment_profiles() -> list[dict]:
    raw = _load_yaml(os.path.join(_DATA_DIR, 'constraints', 'equipment_profiles.yaml'))
    return raw.get('equipment_profiles', [])


def _injury_flags() -> list[dict]:
    raw = _load_yaml(os.path.join(_DATA_DIR, 'constraints', 'injury_flags.yaml'))
    return raw.get('injury_flags', [])


_BENCHMARK_CATEGORY_MAP = {
    'max_strength': 'strength', 'power': 'strength', 'relative_strength': 'strength',
    'strength_endurance': 'conditioning', 'aerobic_base': 'conditioning',
    'anaerobic_intervals': 'conditioning',
}
_BENCHMARK_UNIT_MAP = {'bw_ratio': '×BW', 'reps': ' reps', 'time_minutes': ' min'}
_CELL_EXTRACT = {
    ('hips', 'back_squat'):           ('male_bw_pct', '×BW',   False, 'Back Squat'),
    ('hips', 'broad_jump'):           ('metres',      ' m',    False, 'Broad Jump'),
    ('push', 'shoulder_press'):       ('male_bw_pct', '×BW',   False, 'Shoulder Press'),
    ('push', 'thruster'):             ('male_bw_pct', '×BW',   False, 'Thruster'),
    ('pull', 'deadlift'):             ('male_bw_pct', '×BW',   False, 'Deadlift'),
    ('pull', 'power_clean'):          ('male_bw_pct', '×BW',   False, 'Power Clean'),
    ('core', 'four_point_ab_bridge'): ('time_min',    ' min',  False, 'Plank Hold'),
    ('skill', 'double_under'):        ('reps',        ' reps', False, 'Double-Under'),
    ('endurance', 'run_400m'):        ('male_time',   ' min',  True,  '400m Run'),
    ('endurance', 'run_800m'):        ('male_time',   ' min',  True,  '800m Run'),
    ('endurance', 'row_500m'):        ('male_time',   ' min',  True,  '500m Row'),
}


def _parse_time(t: str) -> float:
    parts = str(t).split(':')
    return round(int(parts[0]) + int(parts[1]) / 60, 3)


def _cell_benchmarks() -> list[dict]:
    path = os.path.join(_DATA_DIR, 'benchmarks', 'cell_standards.yaml')
    data = _load_yaml(path) or {}
    standards_data = data.get('standards', {})
    level_map = [('I', 'entry'), ('II', 'intermediate'), ('III', 'advanced'), ('IV', 'elite')]
    result = []
    for (domain, exercise), (key, unit, lower, name) in _CELL_EXTRACT.items():
        ex_data = standards_data.get(domain, {}).get(exercise, {})
        levels_data = ex_data.get('levels', {})
        standards: dict[str, float] = {}
        for roman, level_name in level_map:
            lvl = levels_data.get(roman, {})
            val = lvl.get(key)
            if val is None:
                break
            standards[level_name] = _parse_time(val) if key == 'male_time' else float(val)
        if len(standards) < 4:
            continue
        result.append({
            'id': f'cell_{domain}_{exercise}', 'name': name, 'category': 'cell',
            'domain': domain, 'unit': unit, 'standards': standards, 'lower_is_better': lower,
        })
    return result


def _all_benchmarks() -> list[dict]:
    result = []
    for fname in ('strength_standards.yaml', 'conditioning_standards.yaml'):
        path = os.path.join(_DATA_DIR, 'benchmarks', fname)
        items = _load_yaml(path) or []
        for item in items:
            domain = item.get('domain', '')
            metric_type = item.get('metric_type', '')
            levels = item.get('levels', {})
            standards: dict[str, float] = {}
            for lvl in ('entry', 'intermediate', 'advanced', 'elite'):
                lvl_data = levels.get(lvl, {})
                val = lvl_data.get('male') if isinstance(lvl_data, dict) else None
                if val is not None:
                    standards[lvl] = val
            if len(standards) < 4:
                continue
            b: dict = {
                'id': item['id'], 'name': item['name'],
                'category': _BENCHMARK_CATEGORY_MAP.get(domain, 'conditioning'),
                'unit': _BENCHMARK_UNIT_MAP.get(metric_type, ''),
                'standards': standards,
                'lower_is_better': bool(item.get('lower_is_better', False)),
            }
            if item.get('notes'):
                b['notes'] = item['notes'].strip()
            result.append(b)
    result.extend(_cell_benchmarks())
    return result


def _write(filename: str, data: object) -> None:
    path = os.path.join(_OUT_DIR, filename)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f'  wrote {path} ({os.path.getsize(path) // 1024} KB)')


def main() -> None:
    os.makedirs(_OUT_DIR, exist_ok=True)
    print('Dumping static reference data...')
    _write('goals.json', _all_goals())
    _write('exercises.json', _all_exercises())
    _write('modalities.json', _all_modalities())
    _write('frameworks.json', _all_frameworks())
    _write('philosophies.json', _all_philosophies())
    _write('equipment_profiles.json', _equipment_profiles())
    _write('injury_flags.json', _injury_flags())
    _write('benchmarks.json', _all_benchmarks())
    print('Done.')


if __name__ == '__main__':
    main()
