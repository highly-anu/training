#!/usr/bin/env python
"""Test script to generate a Wildman program and verify session durations."""
import json
import sys
from src.generator import generate
from src.validator import validate
from src import goals, loader

# Force UTF-8 for Windows console
sys.stdout.reconfigure(encoding='utf-8') if hasattr(sys.stdout, 'reconfigure') else None

constraints = {
    'equipment': ['kettlebell'],
    'days_per_week': 4,
    'session_time_minutes': 60,
    'training_level': 'intermediate',
    'training_phase': 'base',
}

print('Generating Wildman KB program...')
print(f'Constraints: {json.dumps(constraints, indent=2)}')
print()

# Load philosophy and convert to goal (same as API does)
phil_id = 'wildman_kettlebell'
phil = loader.load_philosophy(phil_id)
all_frameworks = loader.load_all_frameworks()

# Build the synthetic goal exactly the way the API does.
goal_dict = goals.philosophy_to_goal(phil_id, list(all_frameworks.values()))
priorities = goal_dict['priorities']
primary_fw_id = goal_dict['framework_selection']['default_framework']

print(f'Using framework: {primary_fw_id}')
print(f'Priorities: {json.dumps(priorities, indent=2)}')
print()

result = generate(
    goal_id=None,
    constraints=constraints,
    num_weeks=4,
    output_format='dict',
    goal_dict=goal_dict,
)

# Save full output
with open('wildman_program_output.json', 'w', encoding='utf-8') as f:
    json.dump(result, f, indent=2)

print(f'[OK] Generated {len(result["weeks"])} weeks')
print(f'[OK] Full output saved to: wildman_program_output.json')
print()

# Analyze Week 1 sessions
week1 = result['weeks'][0]
print('=== WEEK 1 SESSION ANALYSIS ===')
print()

for day_name, sessions in week1['schedule'].items():
    if not sessions:
        print(f'{day_name}: Rest')
        continue

    for idx, session in enumerate(sessions):
        session_num = idx + 1 if len(sessions) > 1 else ''
        print(f'{day_name} {session_num}:' if session_num else f'{day_name}:')
        print(f'  Modality: {session.get("modality", "N/A")}')
        print(f'  Archetype: {session.get("archetype_name", "N/A")} ({session.get("archetype_id", "N/A")})')

        # Calculate total session time
        total_minutes = 0
        slot_durations = []

        for slot in session.get('slots', []):
            exercise = slot.get('exercise', {})
            load = slot.get('load_prescription', {})

            # Check for duration fields
            duration_min = load.get('duration_minutes')

            if duration_min is not None:
                total_minutes += duration_min
                status = '[OK]' if duration_min < 90 else '[!!!]'
                slot_durations.append(f'{duration_min}min')
                print(f'    {status} {slot.get("role", "unknown")}: {exercise.get("name", "N/A")} - {duration_min} min')
            else:
                # Sets/reps based
                sets = load.get('sets', '')
                reps = load.get('reps', '')
                weight = load.get('weight_kg', '')
                if sets and reps:
                    print(f'    [-] {slot.get("role", "unknown")}: {exercise.get("name", "N/A")} - {sets}x{reps}' + (f' @ {weight}kg' if weight else ''))

        if total_minutes > 0:
            status_icon = '[OK]' if total_minutes <= 60 else '[WARNING]'
            print(f'  {status_icon} Total: {total_minutes} min ({" + ".join(slot_durations)}) | constraint: <=60 min')
        print()

# Summary
print('=== SUMMARY ===')
total_sessions = sum(len(sessions) for sessions in week1['schedule'].values())
print(f'Total sessions in Week 1: {total_sessions}')
# generate() returns the raw program; validation is a separate pre-flight step
# (api.py runs it before generating). Run it here the same way.
data = loader.load_all_data()
archetypes = [a for a in data['archetypes'] if a.get('_package') == phil_id]
validation = validate(goal_dict, constraints, archetypes,
                      data['modalities'], data['injury_flags'])
print(f'Validation feasible: {validation.feasible}')
if validation.errors:
    print(f'Errors: {[e["code"] for e in validation.errors]}')
if validation.warnings:
    print(f'Warnings: {[w["code"] for w in validation.warnings]}')
assert validation.feasible, validation.errors
assert total_sessions > 0, 'no sessions generated'
