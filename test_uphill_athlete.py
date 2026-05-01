#!/usr/bin/env python
"""Test script to generate an Uphill Athlete program and verify session durations."""
import json
import sys
from src.generator import generate
from src import loader

# Force UTF-8 for Windows console
sys.stdout.reconfigure(encoding='utf-8') if hasattr(sys.stdout, 'reconfigure') else None

constraints = {
    'equipment': ['barbell', 'pull_up_bar', 'rower'],
    'days_per_week': 5,
    'session_time_minutes': 90,
    'training_level': 'intermediate',
    'training_phase': 'base',
}

print('Generating Uphill Athlete program...')
print(f'Constraints: {json.dumps(constraints, indent=2)}')
print()

# Load philosophy and convert to goal
phil_id = 'uphill_athlete'
phil = loader.load_philosophy(phil_id)
all_frameworks = loader.load_all_frameworks()

# Find primary framework
fw_candidates = [f for f in all_frameworks.values() if f.get('source_philosophy') == phil_id]
primary_fw_id = fw_candidates[0]['id'] if fw_candidates else 'concurrent_training'
primary_fw = all_frameworks.get(primary_fw_id, {})
sessions = primary_fw.get('sessions_per_week', {})
total = sum(sessions.values()) or 1
priorities = {mod: count / total for mod, count in sessions.items()}

# Build synthetic goal
goal_dict = {
    'id': f'_phil_{phil_id}',
    'name': phil.get('name', phil_id),
    'priorities': priorities,
    'primary_sources': [phil_id],
}

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
with open('uphill_athlete_program_output.json', 'w', encoding='utf-8') as f:
    json.dump(result, f, indent=2)

print(f'[OK] Generated {len(result["weeks"])} weeks')
print(f'[OK] Full output saved to: uphill_athlete_program_output.json')
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
        day_names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
        day_label = day_names[int(day_name) - 1]

        print(f'{day_label} {session_num}:' if session_num else f'{day_label}:')
        print(f'  Modality: {session.get("modality", "N/A")}')

        archetype = session.get('archetype')
        if archetype:
            archetype_name = archetype.get('name', 'N/A')
            archetype_id = archetype.get('id', 'N/A')
            expected_duration = archetype.get('duration_estimate_minutes', '?')
            print(f'  Archetype: {archetype_name} ({archetype_id})')
            print(f'  Expected duration: ~{expected_duration} min')
        else:
            print(f'  Archetype: None (fallback session)')
            expected_duration = '?'

        # Calculate total session time
        total_minutes = 0
        slot_durations = []
        has_time_slots = False

        for slot in session.get('exercises', []):
            exercise = slot.get('exercise', {})
            slot_info = slot.get('slot', {})
            load = slot.get('load', {})

            # Check for duration fields
            duration_min = load.get('duration_minutes')

            if duration_min is not None:
                has_time_slots = True
                total_minutes += duration_min
                status = '[OK]' if duration_min < 90 else '[!!!]'
                slot_durations.append(f'{duration_min}min')
                print(f'    {status} {slot_info.get("role", "unknown")}: {exercise.get("name", "N/A")} - {duration_min} min')
            else:
                # Sets/reps based
                sets = load.get('sets', '')
                reps = load.get('reps', '')
                weight = load.get('weight_kg', '')
                if sets and reps:
                    print(f'    [-] {slot_info.get("role", "unknown")}: {exercise.get("name", "N/A")} - {sets}x{reps}' + (f' @ {weight}kg' if weight else ''))

        if has_time_slots:
            status_icon = '[OK]' if total_minutes <= 90 else '[WARNING]'
            print(f'  {status_icon} Total time-based work: {total_minutes} min ({" + ".join(slot_durations)}) | constraint: <=90 min')
        print()

# Summary
print('=== SUMMARY ===')
total_sessions = sum(len(sessions) for sessions in week1['schedule'].values())
print(f'Total sessions in Week 1: {total_sessions}')
print(f'Days per week: {len([d for d, s in week1["schedule"].items() if s])}/5')

# Check for volume summary
if 'volume_summary' in result:
    vol = result['volume_summary']
    print(f'\nVolume metrics:')
    if 'weekly_sessions' in vol:
        print(f'  Weekly sessions: {vol["weekly_sessions"]}')
    if 'weekly_duration_minutes' in vol:
        print(f'  Weekly duration: {vol["weekly_duration_minutes"]} min')
