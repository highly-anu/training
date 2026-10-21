"""Every package's exercises reach a generated program; orphans may only shrink.

Generates every philosophy x track x level on two qualified profiles (every
piece of the package's own equipment, every required skill, two bells; four
days of 90 minutes and six of 120) and collects what is prescribed. A training
contract's declared substitutes count (prescribed when an injury or the
equipment rules the written movement out), and so does every movement of a
week template's pooled named workout the athlete could be given: a 16-week run
reaches only part of Horsemen's ~190 workouts, which rotate over a macro run
two or three times.

An exercise nothing reaches is an orphan: a movement the package describes and
never prescribes. tools/exercise_coverage_baseline.json records today's per
package; a new one fails, and --update-baseline records a shrunk list. This
checks reachability, not whether an arbitrary athlete should do every lift. No
logs, persistence or server; the generator only.

    python tools/check_exercise_coverage.py [package ...] [--update-baseline]
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from src import generator, goals, loader  # noqa: E402

BASELINE = Path(__file__).with_name('exercise_coverage_baseline.json')
PROFILES = ((4, 90), (6, 120))


def _pooled(framework: dict, archetypes: dict, level: str, equipment: set) -> set:
    """Movements of the template pools' workouts this level and equipment
    could be given (src/week_template.py picks them in rotation)."""
    out = set()
    for cat in (framework.get('categories') or {}).values():
        for aid in cat['archetypes']:
            arch = archetypes.get(aid) or {}
            if arch.get('training_levels') and level not in arch['training_levels']:
                continue
            if not set(arch.get('required_equipment') or []) <= equipment | {'open_space'}:
                continue
            out |= {eid for slot in arch.get('slots') or []
                    for eid in (slot.get('exercise_filter') or {}).get('exercise_ids') or []}
    return out


def reachable(philosophy: dict, catalog: dict, frameworks: dict, archetypes: dict) -> tuple[set, list[str]]:
    used: set = set()
    lines = []
    equipment = sorted({item for e in catalog.values() for item in e.get('equipment', [])} | {'open_space'})
    for track in philosophy.get('tracks') or []:
        goal = goals.philosophy_to_goal(philosophy['id'], list(frameworks.values()), track['id'])
        contract = goal.get('training_contract')
        levels = contract['training_levels'] if contract else ['novice', 'intermediate', 'advanced', 'elite']
        weeks = sum(p['weeks'] for p in goal['phase_sequence'])
        for level in levels:
            for days, minutes in PROFILES:
                constraints = dict(
                    equipment=equipment, kettlebell_count=2, training_level=level,
                    days_per_week=days, session_time_minutes=minutes,
                    mastered_exercises=sorted({eid for m in (contract or {}).get('modules', [])
                                               for eid in m.get('requires_mastery', [])}))
                program = generator.generate(None, constraints, num_weeks=weeks, goal_dict=goal, output_format='dict')
                sessions = [s for w in program.get('weeks') or [] for day in w['schedule'].values() for s in day]
                ids = {ea['exercise']['id'] for s in sessions for ea in s['exercises'] if ea.get('exercise')}
                if contract:
                    placed = {m['id'] for s in sessions for m in s.get('modules') or []}
                    ids |= {alt for m in contract['modules'] if m['id'] in placed
                            for b in m['blocks'] for alt in b.get('alternatives') or []}
                for ph in goal['phase_sequence']:
                    if ph.get('week_templates'):
                        ids |= _pooled(frameworks.get(ph['framework_id']) or {}, archetypes, level, set(equipment))
                used |= ids
                lines.append(f"  {track['id']} | {level} | {days}d {minutes}m | {len(sessions)} sessions | "
                             f"{len(ids & catalog.keys())} / {len(catalog)}")
    return used, lines


def _borrowers(philosophies: list[dict]) -> dict[str, set]:
    """Package id -> the packages that declare `borrows_from` it."""
    out: dict = {}
    for p in philosophies:
        for entry in p.get('borrows_from') or []:
            out.setdefault(entry['package'], set()).add(p['id'])
    return out


def borrowers_of(packages: list[str]) -> set:
    """The packages whose programs can reach `packages`' exercises: themselves
    and every package that borrows from one of them."""
    borrowers = _borrowers(loader.load_philosophies())
    return set(packages) | {b for pkg in packages for b in borrowers.get(pkg, ())}


def reach_of(pkg: str) -> set:
    """Every exercise id the package's own programs prescribe (any package's).
    Loads its own data, so a process pool can run one package per worker."""
    _, catalogs = loader.load_all_exercises()
    frameworks = loader.load_all_frameworks()
    archetypes = {a['id']: a for a in loader.load_all_archetypes()}
    philosophy = next(p for p in loader.load_philosophies() if p['id'] == pkg)
    return reachable(philosophy, catalogs.get(pkg, {}), frameworks, archetypes)[0]


def orphans_of(pkg: str, reached: dict) -> list[str]:
    """`pkg`'s catalog exercises no program reaches, given `reached`
    (package -> reach_of) for the package and every borrower of it."""
    _, catalogs = loader.load_all_exercises()
    catalog = catalogs.get(pkg, {})
    borrowers = _borrowers(loader.load_philosophies())
    used = set(reached.get(pkg, set())).union(*(reached.get(b, set()) for b in borrowers.get(pkg, ())))
    return sorted(catalog.keys() - used)


def run(packages: list[str] | None = None, update: bool = False) -> dict:
    _, catalogs = loader.load_all_exercises()
    frameworks = loader.load_all_frameworks()
    archetypes = {a['id']: a for a in loader.load_all_archetypes()}
    baseline = json.loads(BASELINE.read_text()) if BASELINE.exists() else {}
    orphans: dict = {}
    new: dict = {}
    philosophies = loader.load_philosophies()
    borrowers = _borrowers(philosophies)
    wanted = set(packages) if packages else {p['id'] for p in philosophies}
    # A package's exercise is reached by its own programs, or by those of a
    # package that borrows from it (Uphill's strength days prescribe Starting
    # Strength's lifts).
    run_for = wanted | {b for pkg in wanted for b in borrowers.get(pkg, ())}
    reached, logs = {}, {}
    for philosophy in philosophies:
        if philosophy['id'] in run_for:
            reached[philosophy['id']], logs[philosophy['id']] = reachable(
                philosophy, catalogs.get(philosophy['id'], {}), frameworks, archetypes)
    for philosophy in philosophies:
        pkg = philosophy['id']
        if pkg not in wanted:
            continue
        catalog = catalogs.get(pkg, {})
        used = (reached[pkg] | set().union(*(reached[b] for b in borrowers.get(pkg, ())))) & catalog.keys()
        lines = logs[pkg]
        orphans[pkg] = sorted(catalog.keys() - used)
        new[pkg] = sorted(set(orphans[pkg]) - set(baseline.get(pkg, [])))
        print(f"{pkg}: {len(used)}/{len(catalog)} reachable; orphaned {orphans[pkg] or 'none'}")
        if '-v' in sys.argv:
            print('\n'.join(lines))
    if update:
        merged = {**baseline, **orphans}
        BASELINE.write_text(json.dumps(merged, indent=2, sort_keys=True) + '\n')
        print(f'baseline written: {sum(len(v) for v in merged.values())} orphan(s)')
        return orphans
    gone = {pkg: sorted(set(baseline.get(pkg, [])) - set(o)) for pkg, o in orphans.items()}
    if any(gone.values()):
        print('no longer orphaned (run --update-baseline to drop them):',
              {k: v for k, v in gone.items() if v})
    failing = {k: v for k, v in new.items() if v}
    if failing:
        raise AssertionError(f'Catalog exercises with no generated program path: {failing}')
    print(f'Package coverage: {sum(len(v) for v in orphans.values())} orphan(s), all in the baseline')
    return orphans


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('-')]
    run(args or None, update='--update-baseline' in sys.argv)
