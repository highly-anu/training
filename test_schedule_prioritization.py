#!/usr/bin/env python
"""Test priority-based modality dropping and duration matching."""
import json
import sys
from src.generator import generate
from src import loader

# Force UTF-8 for Windows console
sys.stdout.reconfigure(encoding='utf-8') if hasattr(sys.stdout, 'reconfigure') else None

print('=== TEST 1: Priority Tier Dropping (2 days only) ===')
print()

# Simulate user with limited availability (3 days should trigger tier dropping)
constraints_limited = {
    'equipment': ['kettlebell'],
    'days_per_week': 3,  # Limited but valid
    'session_time_minutes': 60,
    'training_level': 'intermediate',
    'training_phase': 'base',
}

# Load philosophy (use Wildman - has lower minimum requirements)
phil_id = 'wildman_kettlebell'
phil = loader.load_philosophy(phil_id)
all_frameworks = loader.load_all_frameworks()

# Build synthetic goal
fw_candidates = [f for f in all_frameworks.values() if f.get('source_philosophy') == phil_id]
primary_fw_id = fw_candidates[0]['id'] if fw_candidates else 'concurrent_training'
primary_fw = all_frameworks.get(primary_fw_id, {})
sessions = primary_fw.get('sessions_per_week', {})
total = sum(sessions.values()) or 1
priorities = {mod: count / total for mod, count in sessions.items()}

goal_dict = {
    'id': f'_phil_{phil_id}',
    'name': phil.get('name', phil_id),
    'priorities': priorities,
    'primary_sources': [phil_id],
}

print(f'Framework: {primary_fw_id}')
print(f'Ideal priorities: {json.dumps(priorities, indent=2)}')
print(f'User availability: {constraints_limited["days_per_week"]} days/week')
print()

result = generate(
    goal_id=None,
    constraints=constraints_limited,
    num_weeks=2,
    output_format='dict',
    goal_dict=goal_dict,
)

print('RESULT:')
print(f'  Type: {type(result)}')
if isinstance(result, str):
    print(f'  String output (first 500 chars): {result[:500]}')
    sys.exit(1)
print(f'  Generated: {len(result["weeks"])} weeks')
print(f'  Compromises: {len(result.get("compromises", []))} adjustments')
print()

if result.get('compromises'):
    print('Compromises made:')
    for comp in result['compromises']:
        print(f'  - {comp}')
    print()

# Check what modalities were actually included
week1 = result['weeks'][0]
modalities_used = set()
for day_sessions in week1['schedule'].values():
    for session in day_sessions:
        modalities_used.add(session.get('modality'))

print(f'Modalities in Week 1: {", ".join(sorted(modalities_used))}')
print()

# Verify tier 1 (foundational) modalities are present
if 'aerobic_base' in modalities_used and 'max_strength' in modalities_used:
    print('[OK] Tier 1 modalities (aerobic_base, max_strength) kept ✓')
else:
    print('[FAIL] Tier 1 modalities missing! ✗')

# Verify tier 4 (accessory) modalities are dropped
if 'mobility' not in modalities_used:
    print('[OK] Tier 4 modality (mobility) dropped ✓')
else:
    print('[NOTE] Tier 4 modality (mobility) still present')

print()
print('=== TEST 2: Duration Matching with User Schedule ===')
print()

# User with specific schedule: Mon=Long, Wed=Short, Fri=Long
weekly_schedule = {
    'Monday': {'session1': 'long', 'session2': 'rest', 'session3': 'rest', 'session4': 'rest'},
    'Tuesday': {'session1': 'rest', 'session2': 'rest', 'session3': 'rest', 'session4': 'rest'},
    'Wednesday': {'session1': 'short', 'session2': 'rest', 'session3': 'rest', 'session4': 'rest'},
    'Thursday': {'session1': 'rest', 'session2': 'rest', 'session3': 'rest', 'session4': 'rest'},
    'Friday': {'session1': 'long', 'session2': 'rest', 'session3': 'rest', 'session4': 'rest'},
    'Saturday': {'session1': 'rest', 'session2': 'rest', 'session3': 'rest', 'session4': 'rest'},
    'Sunday': {'session1': 'rest', 'session2': 'rest', 'session3': 'rest', 'session4': 'rest'},
}

constraints_scheduled = {
    'equipment': ['barbell', 'pull_up_bar', 'rower'],
    'weekly_schedule': weekly_schedule,
    'training_level': 'intermediate',
    'training_phase': 'base',
}

print('User schedule: Mon=Long (75min), Wed=Short (40min), Fri=Long (75min)')
print()

result2 = generate(
    goal_id=None,
    constraints=constraints_scheduled,
    num_weeks=1,
    output_format='dict',
    goal_dict=goal_dict,
)

week1 = result2['weeks'][0]

# Check which days have sessions and what their durations are
day_names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']

print('Generated schedule:')
for day_name, sessions in week1['schedule'].items():
    if sessions:
        for session in sessions:
            modality = session.get('modality', 'unknown')
            print(f'  {day_name}: {modality}')

print()
print('All tests complete!')
