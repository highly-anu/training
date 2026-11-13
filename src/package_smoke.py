"""Does a package generate? Every phase of every track, on the framework that
phase names — the loop tools/check_styles.py runs for every package, here for
one, returning what it found instead of printing it. And the provenance audit
of a generated program (tools/check_provenance.py's), so the gate can read
the programs the smoke run already built.

Both tools call this module; src/package_gate.py calls it for one folder.
"""
from __future__ import annotations

from collections import Counter

from src import goals, implements, loader, phases, provenance
from src.generator import generate
from src.package_eval import ALL_EQUIPMENT
from src.validator import validate


def days_for(track: dict, fw_by_id: dict) -> int:
    """A day count every framework in the track accepts, nearest the first
    phase's ideal."""
    first = fw_by_id.get(track['phases'][0]['framework_id'], {})
    exp = first.get('expectations', {})
    want = exp.get('ideal_days_per_week') or exp.get('min_days_per_week', 4)
    lo, hi = 1, 7
    for ph in track['phases']:
        aw = fw_by_id.get(ph['framework_id'], {}).get('applicable_when', {})
        lo = max(lo, aw.get('days_per_week_min', 1))
        hi = min(hi, aw.get('days_per_week_max', 7))
    return min(max(want, lo), hi)


def test_problems(weeks: list, ph: dict) -> list[str]:
    """Each week of a phase that tests: every declared test placed."""
    from src import standard_tests
    problems = []
    for w in weeks:
        entry = {'tests': ph['tests'], 'phase_weeks': ph['weeks'], 'repeatable': ph.get('repeatable'),
                 'week_in_phase': w.get('week_in_phase')}
        want = standard_tests.tests_for_week(entry)
        got = [s for day in (w.get('schedule') or {}).values() for s in day if s.get('test')]
        if len(got) != len(want):
            why = [t.get('reason') for t in w.get('tests_skipped') or []]
            problems.append(f"week {w.get('week_in_phase')}: {len(got)} of {len(want)} tests placed {why or ''}".rstrip())
    return problems


def phase_constraints(goal: dict, ph: dict, fw: dict, days: int) -> dict:
    """An intermediate with every piece of equipment and no injury, at the
    framework's ideal minutes, starting on this phase — so nothing but the
    package is the reason a phase fails. A contract track takes a level it is
    written for, its implements confirmed and its required movements mastered."""
    exp = fw.get('expectations', {})
    constraints = {
        'days_per_week': days,
        'session_time_minutes': exp.get('ideal_session_minutes') or exp.get('min_session_minutes', 60),
        'training_level': 'intermediate',
        'equipment': ALL_EQUIPMENT,
        'injury_flags': [],
        'start_phase': ph['id'],
        'periodization_week': 1,
        'fatigue_state': 'normal',
    }
    contract = goal.get('training_contract')
    if contract:
        # A level the track is written for (Starting Strength's novice
        # progression refuses an intermediate).
        levels = contract['training_levels']
        if constraints['training_level'] not in levels:
            constraints['training_level'] = levels[0]
        constraints = implements.confirm(constraints, contract)
        constraints['mastered_exercises'] = sorted({eid for m in contract['modules']
                                                    for eid in m.get('requires_mastery', [])})
    return constraints


def smoke_phase(phil_id: str, track: dict, ph: dict, goal: dict, days: int, fw_by_id: dict, data: dict,
                archetypes: list) -> dict:
    """One phase: validated, one week generated from its own start, the
    week's framework compared with the one the phase declares; a phase that
    tests is then generated at full length and every declared test must be
    placed. → {label, ok, days, sessions, why, missing_framework,
    test_problems (None when the phase declares none or did not generate),
    program (the one-week program, for the provenance audit)}."""
    label = f"{phil_id}/{track['id']}/{ph['id']}"
    out = {'label': label, 'ok': False, 'days': days, 'sessions': 0, 'why': None,
           'missing_framework': None, 'test_problems': None, 'program': None}
    fw = fw_by_id.get(ph['framework_id'])
    if fw is None:
        out['missing_framework'] = ph['framework_id']
        out['why'] = f"framework '{ph['framework_id']}' not found"
        return out
    constraints = phase_constraints(goal, ph, fw, days)
    result = validate(goal, constraints, archetypes, data['modalities'], data['injury_flags'])
    sessions, ran = 0, None
    if result.feasible:
        raw = generate(goal_id=goal['id'], goal_dict=goal, constraints=constraints, num_weeks=1,
                       output_format='dict')
        weeks = raw.get('weeks', [])
        sessions = sum(len(day) for w in weeks for day in w.get('schedule', {}).values())
        ran = weeks[0].get('framework') if weeks else None
        out['program'] = raw
    wrong_fw = ran is not None and ran != ph['framework_id']
    out['sessions'] = sessions
    out['ok'] = bool(result.feasible and sessions > 0 and not wrong_fw)
    codes = [e['code'] for e in result.errors]
    out['why'] = codes or ([f"ran {ran}"] if wrong_fw else 'generated 0 sessions')
    # A phase that tests: generated at full length, every declared test must
    # be placed — an intermediate with every piece of equipment can do each
    # one, so a skip here is authoring.
    if out['ok'] and ph.get('tests'):
        raw = generate(goal_id=goal['id'], goal_dict=goal, constraints=constraints,
                       num_weeks=int(ph['weeks']), output_format='dict')
        out['test_problems'] = test_problems(raw.get('weeks', []), ph)
    return out


def smoke_philosophy(phil: dict, frameworks: list, fw_by_id: dict, data: dict):
    """Every phase of every track of one philosophy, in order (a generator of
    smoke_phase results)."""
    phil_id = phil['id']
    archetypes = [a for a in data['archetypes'] if a.get('_package') == phil_id]
    for track in phases.tracks_of(phil):
        goal = goals.philosophy_to_goal(phil_id, frameworks, track_id=track['id'])
        days = days_for(track, fw_by_id)
        for ph in track['phases']:
            yield smoke_phase(phil_id, track, ph, goal, days, fw_by_id, data, archetypes)


def smoke_package(phil_id: str) -> list[dict]:
    """One package by id, read through the loader: every track and phase."""
    frameworks = list(loader.load_all_frameworks().values())
    fw_by_id = {f['id']: f for f in frameworks}
    data = loader.load_all_data()
    phil = next((p for p in loader.load_philosophies() if p['id'] == phil_id), None)
    if phil is None:
        raise LookupError(f"no philosophy '{phil_id}' among the packages the caller sees")
    return list(smoke_philosophy(phil, frameworks, fw_by_id, data))


# ── Provenance ────────────────────────────────────────────────────────────────

def sessions_of(raw: dict):
    for week in raw.get('weeks', []):
        for day in week.get('schedule', {}).values():
            for session in day:
                yield session


def audit_program(raw: dict, policy, ex_index: dict) -> dict:
    """Return {'archetypes': Counter(package), 'exercises': Counter, 'foreign': [...]}"""
    arch_pkgs: Counter = Counter()
    ex_pkgs: Counter = Counter()
    foreign: list = []

    for session in sessions_of(raw):
        arch = session.get('archetype')
        session_policy = (provenance.SourcePolicy(owner_packages=frozenset({arch.get('_package')}),
                          borrows=policy.borrows, strict=policy.strict) if arch else policy)
        if arch:
            pkg = arch.get('_package')
            arch_pkgs[pkg] += 1
            if not provenance.allows_archetype(arch, policy):
                foreign.append(f"archetype {arch.get('id')} from {pkg}")

        assignments = list(session.get('exercises') or [])
        modality = session.get('modality')
        for assignment in assignments:
            ex = assignment.get('exercise')
            if not ex:
                continue
            full = ex_index.get(ex.get('id'), ex)
            pkgs = provenance.exercise_packages(full)
            ex_pkgs[pkgs[0] if pkgs else None] += 1
            if arch and not provenance.allows_exercise(full, session_policy, modality):
                foreign.append(
                    f"exercise {ex.get('id')} absent from {arch.get('_package')}/exercises.yaml")
            if not provenance.allows_exercise(full, policy, modality):
                foreign.append(f"exercise {ex.get('id')} from {pkgs}")

        # Complementary work drew from the unfiltered global index and is the
        # easiest regression to reintroduce — audit it explicitly.
        for comp in session.get('complementary_work') or []:
            ex = comp.get('exercise') if isinstance(comp, dict) and 'exercise' in comp else comp
            if not isinstance(ex, dict) or 'id' not in ex:
                continue
            full = ex_index.get(ex['id'], ex)
            pkgs = provenance.exercise_packages(full)
            ex_pkgs[pkgs[0] if pkgs else None] += 1
            if arch and not provenance.allows_exercise(full, session_policy):
                foreign.append(
                    f"complementary {ex['id']} absent from {arch.get('_package')}/exercises.yaml")
            if not provenance.allows_exercise(full, policy):
                foreign.append(f"complementary {ex['id']} from {pkgs}")

    return {'archetypes': arch_pkgs, 'exercises': ex_pkgs, 'foreign': foreign}
