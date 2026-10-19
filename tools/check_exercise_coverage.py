"""Generate every supported Wildman track/level; reject orphan catalog entries.

A qualified fixture declares every required skill and two matching bells. This
checks reachability, not whether an arbitrary athlete should perform every lift.
No logs, persistence, server, or automatic mastery inference is used.
"""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from src import generator, goals, loader


def run():
    _, catalogs = loader.load_all_exercises()
    catalog = catalogs['wildman_kettlebell']
    frameworks = list(loader.load_all_frameworks().values())
    equipment = sorted({item for e in catalog.values() for item in e.get('equipment', [])})
    philosophy = loader.load_philosophy('wildman_kettlebell')
    used = set()
    print('Track | Level | Weeks | Sessions | Unique / catalog')
    for track in philosophy['tracks']:
        goal = goals.philosophy_to_goal(philosophy['id'], frameworks, track['id'])
        contract = goal['training_contract']
        for level in ('novice', 'intermediate', 'advanced', 'elite'):
            if level not in contract['training_levels']:
                print(f"{track['id']} | {level} | unsupported")
                continue
            constraints = dict(equipment=equipment, kettlebell_count=2, training_level=level,
                days_per_week=4, session_time_minutes=90,
                mastered_exercises=sorted({eid for m in contract['modules'] for eid in m.get('requires_mastery', [])}))
            weeks = sum(p['weeks'] for p in goal['phase_sequence'])
            program = generator.generate(None, constraints, num_weeks=weeks, goal_dict=goal, output_format='dict')
            if program.get('validation_errors') or len(program['weeks']) != weeks:
                raise AssertionError(f"{track['id']}/{level}: {program.get('validation_errors')}")
            sessions = [s for w in program['weeks'] for day in w['schedule'].values() for s in day]
            ids = {ea['exercise']['id'] for s in sessions for ea in s['exercises'] if ea.get('exercise')}
            if ids - catalog.keys():
                raise AssertionError(f'Foreign exercises: {ids - catalog.keys()}')
            used |= ids
            print(f"{track['id']} | {level} | {weeks} | {len(sessions)} | {len(ids)} / {len(catalog)}")
    orphaned = catalog.keys() - used
    print(f'Package coverage: {len(used)}/{len(catalog)}; orphaned: {sorted(orphaned)}')
    if orphaned:
        raise AssertionError(f'Catalog exercises have no generated program path: {sorted(orphaned)}')
    return used


if __name__ == '__main__':
    run()
