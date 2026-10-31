#!/usr/bin/env python
"""Every phase of every track a philosophy offers must validate and generate,
on the framework that phase names.

Guards two classes of bug. A style the synthetic goal never exposed was
rejected as another philosophy's (horsemen_gpp/gpp_circuits,
wildman_kettlebell/kb_general_practice). And an explicit pick was silently
overridden: the old check forced a framework and only asserted sessions > 0,
so it passed while every week ran a different framework. Each phase here is
generated from its own start and the week's framework is compared with the
one the phase declares.

Then compositions (src/composition.py): five named ones, and every composable
track — a contract's or a templated one — paired round-robin with others of
its kind and of the other kind (`blend_pairs`), each pair's constraints taken
from the two tracks' own data, so a new package's tracks are blended with no
edit here.

Usage:  .venv/bin/python tools/check_styles.py
Exits non-zero if any philosophy x track x phase fails at its framework's
`expectations`, a composition goes wrong, or a track composes in none of its
pairs.
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src import goals, implements, loader, phases  # noqa: E402
from src.generator import generate  # noqa: E402
from src.validator import validate  # noqa: E402

# Everything, so equipment is never the reason a style fails here.
from src.package_eval import ALL_EQUIPMENT  # noqa: E402


def _days_for(track: dict, fw_by_id: dict) -> int:
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


def _test_problems(weeks: list, ph: dict) -> list[str]:
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


# Compositions (src/composition.py): tracks of different methods, and two of
# one, on one week. Five named ones pin particular claims — an event date that
# ends every track on its last phase, two tracks of one package — (lanes, days,
# minutes, extra constraints, event in weeks); the generated pairs below cover
# every composable track.
_KB = ['wk_kb_clean_single', 'wk_kb_press_single', 'wk_kb_snatch', 'wk_kb_swing_single_arm']
COMPOSITIONS = [
    ([('uphill_athlete', None, 0.6), ('starting_strength', None, 0.4)], 7, 90, {}, None),
    ([('horsemen_gpp', None, 0.5), ('wildman_kettlebell', 'general_practice', 0.5)], 6, 75,
     {'mastered_exercises': _KB}, None),
    ([('wildman_kettlebell', 'general_practice', 0.6), ('wildman_kettlebell', 'snatch_practice', 0.4)], 5, 60,
     {'mastered_exercises': _KB}, None),
    ([('bjj', None, 0.6), ('kelly_starrett', None, 0.4)], 5, 75, {}, None),
    ([('crossfit', None, 0.5), ('starting_strength', None, 0.5)], 5, 75, {}, 12),
]
LEVELS = ['novice', 'intermediate', 'advanced', 'elite']


def composable_tracks() -> list[dict]:
    """Every track a composition can take — a training contract's or a
    templated one (composition.build_lanes) — sorted by `package/track`, with
    what its own data asks for: the first phase's days (`_days_for`) and
    minutes (its framework's `expectations`), the levels it is written for (a
    contract's `training_levels`; a templated track's, every level one of its
    named workouts is written for, since it runs while one fits) and its
    contract."""
    frameworks = list(loader.load_all_frameworks().values())
    fw_by_id = {f['id']: f for f in frameworks}
    archetypes = {a['id']: a for a in loader.load_all_data()['archetypes']}
    out = []
    for phil in sorted(loader.load_philosophies(), key=lambda p: p['id']):
        for track in phases.tracks_of(phil):
            goal = goals.philosophy_to_goal(phil['id'], frameworks, track_id=track['id'])
            contract = goal.get('training_contract')
            if contract:
                levels = set(contract['training_levels'])
            elif any(ph.get('week_templates') for ph in track['phases']):
                levels = set()
                for ph in track['phases']:
                    fw = fw_by_id.get(ph['framework_id'], {})
                    for cid, cat in (fw.get('categories') or {}).items():
                        if cid != fw.get('warm_up_category'):
                            levels |= {lv for aid in cat.get('archetypes') or []
                                       for lv in archetypes.get(aid, {}).get('training_levels') or LEVELS}
            else:
                continue
            exp = fw_by_id.get(track['phases'][0]['framework_id'], {}).get('expectations', {})
            out.append({'key': f"{phil['id']}/{track['id']}", 'philosophy_id': phil['id'], 'track_id': track['id'],
                        'kind': 'contract' if contract else 'template', 'contract': contract,
                        'days': _days_for(track, fw_by_id),
                        'minutes': exp.get('ideal_session_minutes') or exp.get('min_session_minutes', 60),
                        'levels': [lv for lv in LEVELS if lv in levels]})
    return out


def blend_pairs(tracks: list[dict]) -> list[tuple[dict, dict]]:
    """Round-robin pairs: each contract track with the one half the list
    away, each templated track likewise, and each contract track with a
    templated one — so every track is blended with its own kind and with the
    other, and a new package's tracks join with no edit here. A partner the
    track shares no level with, or a pair already made, passes to the next."""
    used: set = set()

    def pick(left, right, start):
        out = []
        for i, a in enumerate(left):
            for j in range(len(right)):
                b = right[(start(i) + j) % len(right)]
                pair = frozenset((a['key'], b['key']))
                if b is a or pair in used or not set(a['levels']) & set(b['levels']):
                    continue
                used.add(pair)
                out.append((a, b))
                break
        return out

    contracts = [t for t in tracks if t['kind'] == 'contract']
    templated = [t for t in tracks if t['kind'] == 'template']
    half_c, half_t = len(contracts) // 2, len(templated) // 2
    pairs = (pick(contracts[:half_c], contracts, lambda i: i + half_c)
             + pick(templated[:half_t], templated, lambda i: i + half_t)
             + pick(contracts, templated, lambda i: i))
    # An odd count, or more of one kind than the other, leaves a track out:
    # it takes the next track after it it shares a level with.
    for n, t in enumerate(tracks):
        if not any(t in pair for pair in pairs):
            pairs += pick([t], tracks, lambda i: n + 1)
    return pairs


def _blend(a: dict, b: dict) -> tuple:
    """A pair as a composition: half each, at a level both are written for
    (intermediate where both are), on the busier track's days and one more,
    with room on a day for a session of each, and the mastery each contract's
    modules ask for (as the single tracks above have it)."""
    shared = [lv for lv in a['levels'] if lv in b['levels']]
    extra = {'training_level': 'intermediate' if 'intermediate' in shared else shared[0],
             'mastered_exercises': sorted({eid for t in (a, b) if t['contract'] for m in t['contract']['modules']
                                           for eid in m.get('requires_mastery', [])})}
    return ([(a['philosophy_id'], a['track_id'], 0.5), (b['philosophy_id'], b['track_id'], 0.5)],
            min(7, max(a['days'], b['days']) + 1), a['minutes'] + b['minutes'], extra, None)


def _compose(lanes, days, minutes, extra, event_weeks) -> tuple[list[str], str | None]:
    """(what is wrong with the composed program, the refusal if it refused).
    Every session runs its own track's phase framework and comes from its own
    track's packages; no day goes past its minutes; with an event, every track
    ends on its last phase. Each contract's implements are confirmed, as a
    single track's are."""
    from datetime import date, timedelta
    from src import composition, provenance
    frameworks = list(loader.load_all_frameworks().values())
    constraints = {'days_per_week': days, 'session_time_minutes': minutes, 'training_level': 'intermediate',
                   'equipment': ALL_EQUIPMENT, 'injury_flags': [], 'fatigue_state': 'normal', **extra}
    request = {'lanes': [{'philosophy_id': p, **({'track_id': t} if t else {}), 'weight': w} for p, t, w in lanes]}
    built = composition.build_lanes(composition.normalise_request(request, constraints), constraints, frameworks)
    for lane in built:
        if lane.contract:
            constraints = implements.confirm(constraints, lane.contract)
    event = date.today() + timedelta(weeks=event_weeks) if event_weeks else None
    raw = composition.generate(built, constraints, num_weeks=event_weeks or 8, event_date=event)
    if not raw.get('weeks'):
        return [], '; '.join(e['message'] for e in raw.get('validation_errors') or []) or 'no weeks, no reason'
    problems = []
    allowed = {l.key: provenance.resolve_source_policy(l.goal).allowed_packages for l in built}
    for w in raw['weeks']:
        lanes_by = {l['lane_key']: l for l in w['lanes']}
        for day, sessions in w['schedule'].items():
            if sum(s['archetype']['duration_estimate_minutes'] for s in sessions) > minutes:
                problems.append(f"week {w['week_number']} day {day} over {minutes} minutes")
            for s in sessions:
                lane = lanes_by[s['lane_key']]
                if s.get('framework') != lane['framework']:
                    problems.append(f"week {w['week_number']}: {s['lane_key']} ran {s.get('framework')}")
                if s['archetype'].get('_package') not in allowed[s['lane_key']]:
                    problems.append(f"week {w['week_number']}: {s['lane_key']} drew {s['archetype'].get('_package')}")
    if event_weeks:
        # Every track ends on the last phase of its track.
        for l in built:
            last = (l.goal.get('phase_sequence') or [{}])[-1].get('phase_id')
            got = next(x['phase_id'] for x in raw['weeks'][-1]['lanes'] if x['lane_key'] == l.key)
            if got != last:
                problems.append(f"{l.key} ends in {got}, not {last}")
    return list(dict.fromkeys(problems)), None


def _check_compositions() -> list[str]:
    """The named compositions must compose. Each generated pair must compose
    cleanly or refuse with the composition's reason (two tracks may not fit
    one week); a track that composes in none of its pairs fails."""
    failures = []
    for job in COMPOSITIONS:
        label = ' + '.join(f"{p}/{t or '-'}" for p, t, _ in job[0])
        problems, refused = _compose(*job)
        problems += [f'refused: {refused}'] if refused else []
        print(f"  {'compose ' + label:52} {'ok' if not problems else 'FAIL ' + '; '.join(problems[:3])}")
        failures += [f"compose {label}: {p}" for p in problems[:3]]

    tracks = composable_tracks()
    composed: set = set()
    for a, b in blend_pairs(tracks):
        job = _blend(a, b)
        label = f"{a['key']} + {b['key']}"
        problems, refused = _compose(*job)
        if not problems and not refused:
            composed |= {a['key'], b['key']}
        state = ('FAIL ' + '; '.join(problems[:3]) if problems
                 else f'refused: {refused[:120]}' if refused else 'ok')
        print(f"  blend {label} ({job[3]['training_level']}, {job[1]} days, {job[2]} min) {state}")
        failures += [f"blend {label}: {p}" for p in problems[:3]]
    for t in tracks:
        if t['key'] not in composed:
            failures.append(f"blend {t['key']}: composes in none of its generated pairs")
    return failures


def main() -> int:
    frameworks = list(loader.load_all_frameworks().values())
    fw_by_id = {f['id']: f for f in frameworks}
    data = loader.load_all_data()

    failures: list[str] = []
    for phil in sorted(loader.load_philosophies(), key=lambda p: p['id']):
        phil_id = phil['id']
        archetypes = [a for a in data['archetypes'] if a.get('_package') == phil_id]

        for track in phases.tracks_of(phil):
            goal = goals.philosophy_to_goal(phil_id, frameworks, track_id=track['id'])
            days = _days_for(track, fw_by_id)
            for ph in track['phases']:
                label = f"{phil_id}/{track['id']}/{ph['id']}"
                fw = fw_by_id.get(ph['framework_id'])
                if fw is None:
                    failures.append(f"{label}: framework '{ph['framework_id']}' not found")
                    print(f"  {label:52} MISSING FRAMEWORK")
                    continue
                exp = fw.get('expectations', {})
                constraints = {
                    'days_per_week': days,
                    'session_time_minutes': exp.get('ideal_session_minutes')
                    or exp.get('min_session_minutes', 60),
                    'training_level': 'intermediate',
                    'equipment': ALL_EQUIPMENT,
                    'injury_flags': [],
                    'start_phase': ph['id'],
                    'periodization_week': 1,
                    'fatigue_state': 'normal',
                }
                if goal.get('training_contract'):
                    # A level the track is written for (Starting Strength's
                    # novice progression refuses an intermediate).
                    levels = goal['training_contract']['training_levels']
                    if constraints['training_level'] not in levels:
                        constraints['training_level'] = levels[0]
                    constraints = implements.confirm(constraints, goal['training_contract'])
                    constraints['mastered_exercises'] = sorted({eid for m in goal['training_contract']['modules']
                        for eid in m.get('requires_mastery', [])})

                result = validate(goal, constraints, archetypes,
                                  data['modalities'], data['injury_flags'])
                sessions, ran = 0, None
                if result.feasible:
                    raw = generate(goal_id=goal['id'], goal_dict=goal,
                                   constraints=constraints, num_weeks=1,
                                   output_format='dict')
                    weeks = raw.get('weeks', [])
                    sessions = sum(len(day) for w in weeks
                                   for day in w.get('schedule', {}).values())
                    ran = weeks[0].get('framework') if weeks else None

                wrong_fw = ran is not None and ran != ph['framework_id']
                ok = result.feasible and sessions > 0 and not wrong_fw
                codes = [e['code'] for e in result.errors]
                why = codes or ([f"ran {ran}"] if wrong_fw else 'generated 0 sessions')
                print(f"  {label:52} days={days} sessions={sessions:3} "
                      f"{'ok' if ok else 'FAIL ' + str(why)}")
                if not ok:
                    failures.append(f"{label}: {why}")

                # A phase that tests: generated at full length, every declared
                # test must be placed — an intermediate with every piece of
                # equipment can do each one, so a skip here is authoring.
                if ok and ph.get('tests'):
                    raw = generate(goal_id=goal['id'], goal_dict=goal, constraints=constraints,
                                   num_weeks=int(ph['weeks']), output_format='dict')
                    problems = _test_problems(raw.get('weeks', []), ph)
                    print(f"  {label + ' (tests)':52} {'ok' if not problems else 'FAIL ' + '; '.join(problems)}")
                    failures += [f"{label}: {p}" for p in problems]

    failures += _check_compositions()

    print()
    if failures:
        print(f"{len(failures)} phase(s) failed:")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("Every philosophy x track x phase validates and generates on its own framework.")
    return 0


if __name__ == '__main__':
    sys.exit(main())
