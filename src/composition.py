"""One program from several tracks: a composition.

The athlete picks two or more tracks — of different philosophies, or two of
one — each with a weight, and gets one program that fits their week. Every
track runs in its own phases and by its own engine, as it would alone: a
training contract keeps its modules, their spacing and their progression
(src/training_contract.py), a templated track its named workouts
(src/week_template.py). What the composition decides is where each track's
work goes in the athlete's week:

- **Days and minutes are shared.** Each week, the contract tracks place first
  (heaviest first), then the templated ones, each into the minutes the earlier
  ones left on every day (`day_room`). A day holds a session of each track that
  fits in it; a placement prefers days nobody trains on and keeps a body
  region another track loaded heavily a day or two away (`others`).
- **Weight decides what thins.** A track's share of the athlete's days
  (largest remainder by weight, never under what it needs) is the days its own
  thinning runs at: a template's `drop_order`, a contract's
  `exposures_by_days`. The rest of a contract is its own.
- **When a week cannot fit, the lightest work gives way, said so.** In order:
  a contract's optional modules, then its weekly volume (one scale for the whole
  program, so the ramp keeps its shape), then one weekly exposure of its most
  frequent module — the track that failed first, then the others. Each cut is a
  compromise naming the track. Only when nothing more can give is the request
  refused, with the reason its engine gave.

A single track never comes here: it generates exactly as it always has
(test_single_lane_golden.py).
"""
from __future__ import annotations

from copy import deepcopy
from dataclasses import dataclass, field
from itertools import combinations

from . import goals, loader, phases, provenance, recovery_regions, training_contract, week_template
from .generator import _build_phase_entries
from .scheduler import _build_day_pool

_DAY_NAMES = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
# A templated day needs at least this many minutes left on a day to go there.
_TEMPLATE_MIN_MINUTES = 20
# How many cuts the ladder may make before it gives up.
_MAX_CUTS = 10
# How many placements a contract's week may look at over the athlete's whole
# week (its own days: the contract's own 500).
_SEARCH = 20000
# Weekly volume is scaled down by this much a step, never below the floor.
_VOLUME_STEP, _VOLUME_FLOOR = 0.8, 0.4


class CompositionError(ValueError):
    """The tracks cannot be composed (an unknown track, a bad weight, or a
    week nothing more can be cut from)."""


def lane_key(philosophy_id: str, track_id: str) -> str:
    return f'{philosophy_id}/{track_id}'


# ── The request ──────────────────────────────────────────────────────────────

def normalise_request(body: dict, constraints: dict) -> list[dict]:
    """The request's tracks as [{philosophy_id, track_id, weight, start_phase?,
    periodization_week?}], heaviest first (the lead: the program's week labels).

    Takes `lanes`, or the blend shape (`philosophy_ids` + `philosophy_weights`
    + one `track_id`: the member that owns it runs it, the others the track
    written for the athlete's level), or `philosophy_id`. A track not named is
    resolved here, so every lane says which it runs."""
    level = constraints.get('training_level')
    if body.get('lanes'):
        raw = []
        for lane in body['lanes']:
            if not isinstance(lane, dict) or not lane.get('philosophy_id'):
                raise CompositionError('Each lane needs a philosophy_id.')
            raw.append(dict(lane))
    elif body.get('philosophy_ids'):
        ids = list(dict.fromkeys(body['philosophy_ids']))
        weights = body.get('philosophy_weights') or {}
        track_id = body.get('track_id') or constraints.get('track_id')
        ordered = sorted(ids, key=lambda pid: -float(weights.get(pid, 1.0 / len(ids))))
        owner = goals._track_owner(ids, track_id, ordered) if track_id else None
        raw = []
        for pid in ids:
            lane = {'philosophy_id': pid, 'weight': weights.get(pid, 1.0 / len(ids))}
            if pid == owner:
                lane['track_id'] = track_id
                for key in ('start_phase', 'periodization_week'):
                    value = body.get(key) or constraints.get(key)
                    if value:
                        lane[key] = value
            raw.append(lane)
    else:
        lane = {'philosophy_id': body.get('philosophy_id'), 'weight': 1}
        if body.get('track_id') or constraints.get('track_id'):
            lane['track_id'] = body.get('track_id') or constraints.get('track_id')
        raw = [lane]
    out, seen = [], set()
    for lane in raw:
        try:
            weight = float(lane.get('weight', 1))
        except (TypeError, ValueError):
            raise CompositionError(f"{lane['philosophy_id']}: its weight must be a number.")
        if not weight > 0:
            raise CompositionError(f"{lane['philosophy_id']}: its weight must be above zero.")
        phil = loader.load_philosophy(lane['philosophy_id'])
        track = goals.select_track(phil, lane.get('track_id'), level)
        key = lane_key(lane['philosophy_id'], track['id'])
        if key in seen:
            raise CompositionError(f"{phil.get('name', lane['philosophy_id'])} — {track.get('name', track['id'])} "
                                   'is named twice.')
        seen.add(key)
        entry = {'philosophy_id': lane['philosophy_id'], 'track_id': track['id'], 'weight': weight}
        for k in ('start_phase', 'periodization_week'):
            if lane.get(k):
                entry[k] = lane[k]
        out.append(entry)
    total = sum(l['weight'] for l in out)
    for l in out:
        l['weight'] = l['weight'] / total
    # Heaviest first; a tie keeps the request's order.
    return sorted(out, key=lambda l: -l['weight'])


def split_days(weights: list[float], total: int, floors: list[int] | None = None) -> list[int]:
    """Each weight's share of `total` days: largest remainder, at least its
    floor (1 by default). Shares may sum past `total` when floors demand it —
    tracks then share days."""
    floors = floors or [1] * len(weights)
    exact = [w * total for w in weights]
    shares = [max(int(x), f) for x, f in zip(exact, floors)]
    left = total - sum(shares)
    for i in sorted(range(len(weights)), key=lambda i: (-(exact[i] - shares[i]), i))[:max(0, left)]:
        shares[i] += 1
    return shares


# ── Lanes ────────────────────────────────────────────────────────────────────

@dataclass
class Lane:
    key: str
    philosophy_id: str
    track_id: str
    weight: float
    name: str
    goal: dict
    kind: str                      # 'contract' | 'template'
    contract: dict | None
    policy: object
    entries: list = field(default_factory=list)
    days: int = 1                  # its share of the athlete's days
    reserved: tuple = ()           # the days it keeps for itself
    cuts: dict = field(default_factory=lambda: {'optional': False, 'volume': 1.0, 'exposures': {}})
    start_phase: str | None = None
    periodization_week: int = 1


def _name(philosophy_id: str, track: dict) -> str:
    phil = loader.load_philosophy(philosophy_id)
    short = phil.get('name', philosophy_id).split(' /')[0].split(' —')[0].strip()
    tracks = phases.tracks_of(phil)
    return short if len(tracks) <= 1 else f"{short} — {track.get('name', track.get('id'))}"


def build_lanes(specs: list[dict], constraints: dict, all_frameworks: list) -> list[Lane]:
    lanes = []
    level = constraints.get('training_level')
    for spec in specs:
        goal = goals.philosophy_to_goal(spec['philosophy_id'], all_frameworks, spec['track_id'], level)
        contract = goal.pop('training_contract', None)
        templated = any(p.get('week_templates') for p in goal.get('phase_sequence') or [])
        if not contract and not templated:
            raise CompositionError(
                f"{goal.get('name', spec['philosophy_id'])} lays out no week of its own (no training contract "
                'or week templates), so it cannot be combined with another track yet.')
        track = phases.find_track(loader.load_philosophy(spec['philosophy_id']), spec['track_id'])
        lanes.append(Lane(
            key=lane_key(spec['philosophy_id'], spec['track_id']), philosophy_id=spec['philosophy_id'],
            track_id=spec['track_id'], weight=spec['weight'], name=_name(spec['philosophy_id'], track),
            goal=goal, kind='contract' if contract else 'template', contract=contract,
            policy=provenance.resolve_source_policy(goal),
            start_phase=spec.get('start_phase'), periodization_week=int(spec.get('periodization_week') or 1)))
    return lanes


def composition_goal(lanes: list[Lane]) -> dict:
    """The program's goal: the lead track's (its phases label the weeks),
    named for all of them, drawing on every track's packages, with each
    track's own phases under `tracks`."""
    lead = lanes[0]
    goal = deepcopy(lead.goal)
    sources = list(dict.fromkeys(l.philosophy_id for l in lanes))
    blended: dict = {}
    for l in lanes:
        for mod, value in (l.goal.get('priorities') or {}).items():
            blended[mod] = blended.get(mod, 0.0) + value * l.weight
    total = sum(blended.values()) or 1.0
    goal.update({
        'id': '_phil_composition',
        'name': ' + '.join(l.name for l in lanes),
        'priorities': {k: v / total for k, v in blended.items()},
        'primary_sources': sources,
        'tracks': [{'lane_key': l.key, 'philosophy_id': l.philosophy_id, 'id': l.track_id, 'name': l.name,
                    'weight': round(l.weight, 4), 'kind': l.kind,
                    'description': (l.goal.get('track') or {}).get('description'),
                    'phase_sequence': l.goal.get('phase_sequence')} for l in lanes],
    })
    alternatives = []
    for l in lanes:
        fs = l.goal.get('framework_selection') or {}
        alternatives += [fs.get('default_framework')] + [a['framework_id'] for a in fs.get('alternatives') or []]
    default = (goal.get('framework_selection') or {}).get('default_framework')
    goal['framework_selection'] = {
        'default_framework': default,
        'alternatives': [{'framework_id': f, 'condition': ''} for f in dict.fromkeys(alternatives) if f and f != default]}
    return goal


def _entries(lane: Lane, num_weeks: int, first_week_number: int, event_date=None) -> list[dict]:
    """The lane's weeks: from its start phase, or — with an event date — ending
    on the event, its first phase stretched (or the start cut) to the program's
    length so every track's last phase lands on the event."""
    seq = lane.goal.get('phase_sequence') or []
    if event_date is None:
        start = phases.resolve_start_phase(seq, lane.start_phase, None)
        return _build_phase_entries(seq, start, lane.periodization_week, num_weeks,
                                    first_week_number=first_week_number)
    whole = _build_phase_entries(seq, None, 1, sum(int(p.get('weeks') or 1) for p in seq))
    if len(whole) >= num_weeks:
        tail = whole[-num_weeks:]
    else:
        first = seq[0]
        extra = num_weeks - len(whole)
        stretched = [phases.week_entry(first, k + 1, 0) for k in range(extra + int(first.get('weeks') or 1))]
        tail = stretched + [e for e in whole if e.get('phase_id') != first.get('phase_id')]
        tail = tail[-num_weeks:]
    return [{**e, 'week_in_program': first_week_number + i} for i, e in enumerate(tail)]


def _template_days(lane: Lane) -> int:
    """The most training days a week of the lane's template has."""
    return max([sum(1 for d in week if d != week_template.REST)
                for p in lane.goal.get('phase_sequence') or [] for week in p.get('week_templates') or []] or [1])


def _floor(lane: Lane) -> int:
    """The fewest days a lane's own thinning can run at: one for a template
    (a template that can fill none of its kept days is given another, see
    `generate`), a contract's `exposures_by_days` (BJJ's classes)."""
    if lane.kind != 'contract':
        return 1
    keys = [min(int(k) for k in m['exposures_by_days']) for m in lane.contract['modules']
            if m.get('exposures_by_days')]
    return max(keys or [1])


def _needed_days(lane: Lane) -> int:
    """The days a lane's most frequent essential module needs in a week."""
    if lane.kind != 'contract':
        return lane.days
    return max([_exposures(m) for m in lane.contract['modules'] if not m.get('optional')] or [1])


def _min_gap(days) -> int:
    """The shortest gap between the days, the week wrapping."""
    days = sorted(days)
    if len(days) < 2:
        return 7
    return min([b - a for a, b in zip(days, days[1:])] + [7 + days[0] - days[-1]])


def reserve_days(lanes: list[Lane], pool: list[int], frameworks: dict) -> None:
    """The days each lane keeps for itself, lightest first: a light track
    that needs its days spaced (three lifting days) gets them, a heavy one the
    rest. Each picks by its own framework's cadence. Kept days are a
    preference — a track may still use another's day when the minutes fit."""
    taken: set = set()
    for lane in sorted(lanes, key=lambda l: (l.weight, l.key)):
        need = max(lane.days, _needed_days(lane))
        free = [d for d in pool if d not in taken]
        if not free:
            lane.reserved = tuple(pool)
            continue
        n = min(need, len(free))
        if lane.kind == 'contract':
            # A contract spaces its sessions: the most evenly spread days.
            picked = max(combinations(free, n), key=lambda days: (_min_gap(days), [-d for d in days]))
        else:
            fw = frameworks.get(lane.entries[0].get('framework_id')) or {}
            picked = _build_day_pool(n, [], [d for d in range(1, 8) if d not in free],
                                     framework_id=fw.get('id', ''), phase=lane.entries[0]['phase'],
                                     week_in_phase=1, framework=fw)
        lane.reserved = tuple(sorted(picked))
        taken |= set(picked)


def derived_contract(contract: dict, cuts: dict, days: int | None = None) -> dict:
    """The contract as the composition runs it: a module's exposures for the
    lane's days resolved (`exposures_by_days`), optional modules out, the
    weekly volume scaled, and named modules' weekly exposures cut — the
    ladder's cuts, applied to the data so the engine and its verifier read one
    contract."""
    c = deepcopy(contract)
    if days is not None:
        for m in c['modules']:
            by_days = m.get('exposures_by_days')
            if by_days:
                counts = {int(k): v for k, v in by_days.items()}
                fitting = [k for k in counts if k <= days]
                if fitting:
                    m['exposures_per_week'] = counts[max(fitting)]
                    del m['exposures_by_days']
    if cuts.get('optional'):
        c['modules'] = [m for m in c['modules'] if not m.get('optional')]
    scale = cuts.get('volume', 1.0)
    if scale != 1.0:
        for m in c['modules']:
            p = m['progression']
            if p['model'] == 'weekly_volume':
                p['start_minutes'] = {lv: v * scale for lv, v in p['start_minutes'].items()}
    for mid, n in (cuts.get('exposures') or {}).items():
        m = next((m for m in c['modules'] if m['id'] == mid), None)
        for _ in range(n if m else 0):
            _cut_exposure(m)
    return c


def _exposures(m: dict) -> int:
    values = [m.get('exposures_per_week') or 0] + list((m.get('exposures_by_phase') or {}).values()) \
        + list((m.get('exposures_by_days') or {}).values())
    return max(values)


def _cut_exposure(m: dict) -> bool:
    """One weekly exposure off a module where it runs most (never under one)."""
    top = _exposures(m)
    if top <= 1:
        return False
    if (m.get('exposures_per_week') or 0) >= top:
        m['exposures_per_week'] = top - 1
    for table in ('exposures_by_phase', 'exposures_by_days'):
        if m.get(table):
            m[table] = {k: (v - 1 if v >= top and v > 1 else v) for k, v in m[table].items()}
    return True


def _cut_options(lane: Lane, blocked: set, failed=None) -> list[tuple]:
    """The cuts the ladder can make on a lane, cheapest first: (minutes it
    frees, kind, module). What a week cost comes from the failure when it was
    this lane's (each module's minutes); else optional work goes first, then
    the volume, then the most frequent module's sessions."""
    if lane.kind != 'contract':
        return []
    current = derived_contract(lane.contract, lane.cuts, lane.days)
    modules = current['modules']
    known = getattr(failed.error, 'module_minutes', None) if failed is not None and failed.lane is lane else None
    out = []
    if (lane.key, 'optional') not in blocked and not lane.cuts['optional'] and any(m.get('optional') for m in modules):
        out.append((0, 'optional', None))
    if (lane.key, 'volume') not in blocked and any(m['progression']['model'] == 'weekly_volume' for m in modules) \
            and lane.cuts['volume'] * _VOLUME_STEP >= _VOLUME_FLOOR - 1e-9:
        volume = getattr(failed.error, 'volume_minutes', None) if known else None
        out.append(((volume or 0) * (1 - _VOLUME_STEP) if known else 1e6, 'volume', None))
    for m in modules:
        if m.get('optional') or m['id'] == current.get('test_module') or _exposures(m) <= 1 \
                or (lane.key, 'exposures', m['id']) in blocked:
            continue
        cost = known.get(m['id'], 1e6) if known else 2e6 - _exposures(m)
        out.append((cost, 'exposures', m['id']))
    return sorted(out, key=lambda o: (o[0], o[1], o[2] or ''))


def _cut_text(lane: Lane, cut: str, others: str) -> str:
    if cut == 'optional':
        return f"{lane.name}: its optional work is left out to fit beside {others}."
    if cut == 'volume':
        return (f"{lane.name}: its weekly volume runs at {round(lane.cuts['volume'] * 100):g} % of the method's "
                f"to fit beside {others}.")
    names = {m['id']: m['name'] for m in lane.contract['modules']}
    parts = [f"{names.get(mid, mid)} {n} session{'s' if n > 1 else ''} a week fewer"
             for mid, n in lane.cuts['exposures'].items() if n]
    return f"{lane.name}: {', '.join(parts)} than the method's, to fit beside {others}."


# ── Generation ───────────────────────────────────────────────────────────────

def _session_minutes(session: dict) -> float:
    return float((session.get('archetype') or {}).get('duration_estimate_minutes') or 0)


def _template_constraints(lane: Lane, entry: dict, base: dict, pool: list[int], room: dict, busy: set) -> dict:
    """The week a templated lane plans on: its share of days, kept off days
    another track trains on while enough free days remain, each day's minutes
    what is left on it."""
    fw = loader.load_all_frameworks().get(entry.get('framework_id')) or {}
    kept, _ = week_template.training_days(entry.get('week_template') or [], lane.days,
                                          entry.get('drop_order') or [], fw.get('categories') or {})
    usable = [d for d in pool if room.get(d, 0) >= _TEMPLATE_MIN_MINUTES]
    free = [d for d in usable if d not in busy]
    own = [d for d in free if d in lane.reserved]
    days = own if len(own) >= len(kept) else free if len(free) >= len(kept) else usable
    configs = base.get('day_configs') or {}
    return {**base, 'days_per_week': lane.days, 'preferred_days': [],
            'forced_rest_days': [d for d in range(1, 8) if d not in days],
            'day_configs': {d: {**(configs.get(d) or {}), 'minutes': room[d]} for d in pool},
            'day_room': {d: room[d] for d in pool}}


def _regions(session: dict, modalities: dict) -> frozenset:
    return recovery_regions.heavy(recovery_regions.session_load(session, modalities))


def _tag(session: dict, lane: Lane, week: dict) -> dict:
    session['lane_key'] = lane.key
    session['track_id'] = lane.track_id
    for key in ('phase', 'phase_id', 'framework', 'week_in_phase'):
        if week.get(key) is not None:
            session.setdefault(key, week[key])
    session.setdefault('is_deload', bool(week.get('is_deload')))
    return session


class _Failed(Exception):
    """A track could not be built; `minutes` is each track's weekly minutes
    so far, `rules` whether its own phase rules (not the week's room) refused."""
    def __init__(self, lane: Lane, error: Exception, minutes: dict | None = None, rules: bool = False,
                 entry: dict | None = None):
        super().__init__(str(error))
        self.lane, self.error, self.minutes, self.rules, self.entry = lane, error, minutes or {}, rules, entry


def _run_once(lanes: list[Lane], constraints: dict, data: dict, injury_flags: dict,
              frameworks: dict, pool: list[int], day_cap: dict, include_trace: bool) -> dict:
    from . import generator
    contract_data = {**data, 'injury_flags': injury_flags}
    runs = {}
    for lane in lanes:
        lane_constraints = {**constraints, 'days_per_week': lane.days}
        if lane.kind == 'contract':
            lane_constraints.update(preferred_days=list(pool),
                                    module_progression_state=(constraints.get('module_progression_states') or {}).get(lane.key))
            lane_constraints.pop('module_progression_states', None)
            if lane_constraints['module_progression_state'] is None:
                lane_constraints.pop('module_progression_state')
            contract = derived_contract(lane.contract, lane.cuts, lane.days)
            try:
                runs[lane.key] = (training_contract.start(contract, lane.entries, lane_constraints, contract_data,
                                                          lane.policy, frameworks), lane_constraints, contract)
            except training_contract.ContractError as exc:
                raise _Failed(lane, exc)
        else:
            lib = provenance.scope(data, lane.policy)
            run = generator.start(lane.goal, lane_constraints, data, lib, lane.policy,
                                  {**lib['injury_flags'], **injury_flags}, include_trace)
            run.prime(lane.entries)
            runs[lane.key] = (run, lane_constraints, None)

    # Contracts place before templates (a template day takes whatever room a
    # day has); among them the lightest first, on the days it keeps, so a
    # light track's spaced days are there before a heavy one fills the week
    # around them.
    order = sorted((l for l in lanes if l.kind == 'contract'), key=lambda l: (l.weight, l.key)) \
        + [l for l in lanes if l.kind != 'contract']
    weeks = []
    # Each track's minutes over the weeks built so far, and how many weeks.
    spent: dict[str, list] = {l.key: [0.0, 0] for l in lanes}

    def minutes() -> dict:
        return {k: total / n for k, (total, n) in spent.items() if n}
    for i in range(len(lanes[0].entries)):
        room = dict(day_cap)
        others: dict[int, frozenset] = {}
        lane_weeks: dict[str, dict] = {}
        for lane in order:
            run, lane_constraints, _ = runs[lane.key]
            entry = lane.entries[i]
            if lane.kind == 'contract':
                # Days another lane keeps count as taken even before it trains on them.
                kept = {d: frozenset() for d in pool if d not in lane.reserved}
                try:
                    # Its own days first; the week's other days only when its
                    # work does not fit on them (a failed placement changes
                    # nothing, so the week is simply asked again).
                    try:
                        week = run.week(entry, day_room=room, others={**kept, **others},
                                        essential_days=set(lane.reserved))
                    except training_contract.ContractError:
                        # Every day of the week is a far larger search.
                        week = run.week(entry, day_room=room, others={**kept, **others}, search=_SEARCH)
                except training_contract.ContractError as exc:
                    asked = minutes()
                    if getattr(exc, 'week_minutes', None) is not None:
                        asked[lane.key] = max(asked.get(lane.key, 0), exc.week_minutes)
                    raise _Failed(lane, exc, asked, entry=entry)
            else:
                for d, regions in others.items():
                    run.note_regions(i, d, regions)
                plan = _template_constraints(lane, entry, lane_constraints, pool, room, set(others))
                week = run.week(i, entry, plan)
            for d, sessions in week['schedule'].items():
                for s in sessions:
                    room[d] = room.get(d, 0) - _session_minutes(s)
                    others[d] = others.get(d, frozenset()) | _regions(s, data['modalities'])
                    spent[lane.key][0] += _session_minutes(s)
            spent[lane.key][1] += 1
            lane_weeks[lane.key] = week
        weeks.append(lane_weeks)

    programs = {}
    for lane in lanes:
        run, lane_constraints, contract = runs[lane.key]
        if lane.kind == 'contract':
            try:
                program = run.finish(include_trace)
                training_contract.verify_phase_rules(program, lane.goal)
            except training_contract.ContractError as exc:
                raise _Failed(lane, exc, minutes(), rules=True)
        else:
            program = run.finish(lane.entries, 'dict')
            if program.get('validation_errors'):
                raise _Failed(lane, CompositionError('; '.join(e['message'] for e in program['validation_errors'])),
                              minutes(), rules=True)
        programs[lane.key] = program
    return {'weeks': weeks, 'programs': programs}


def _merge(lanes: list[Lane], result: dict, pool: list[int], day_cap: dict) -> dict:
    """The tracks' weeks as one program: every day's sessions in track order,
    each tagged with its track; the week labelled by the lead track, a deload
    only when every track deloads."""
    lead = lanes[0]
    out_weeks = []
    for lane_weeks in result['weeks']:
        first = lane_weeks[lead.key]
        schedule: dict[int, list] = {}
        summary = []
        for lane in lanes:
            week = lane_weeks[lane.key]
            for d, sessions in week['schedule'].items():
                schedule.setdefault(d, []).extend(_tag(s, lane, week) for s in sessions)
            summary.append({'lane_key': lane.key, 'track_id': lane.track_id,
                            **{k: week.get(k) for k in ('phase', 'phase_id', 'phase_name', 'week_in_phase', 'framework')},
                            'is_deload': bool(week.get('is_deload')),
                            'sessions': sum(len(ss) for ss in week['schedule'].values()),
                            **{k: week[k] for k in ('modules_skipped', 'tests_skipped') if week.get(k)}})
        for d, sessions in schedule.items():
            total = sum(_session_minutes(s) for s in sessions)
            if total > day_cap.get(d, 0) + 1e-9:
                raise CompositionError(f'{_DAY_NAMES[d - 1]}: the tracks need {total:g} minutes; '
                                       f'{day_cap.get(d, 0):g} are available.')
        week_out = {
            'week_number': first['week_number'], 'week_in_phase': first['week_in_phase'],
            'phase': first['phase'], 'is_deload': all(s['is_deload'] for s in summary),
            'schedule': dict(sorted(schedule.items())), 'framework': first.get('framework'),
            'lanes': summary,
        }
        for key in ('phase_id', 'phase_name'):
            if first.get(key):
                week_out[key] = first[key]
        week_out['track_id'] = lead.track_id
        skipped = [{**t, 'lane_key': s['lane_key']} for s in summary for t in s.get('tests_skipped') or []]
        if skipped:
            week_out['tests_skipped'] = skipped
        out_weeks.append(week_out)

    compromises: list[str] = []
    composition_lanes = []
    reports = []
    for lane in lanes:
        program = result['programs'][lane.key]
        for line in program.get('compromises') or []:
            text = f'{lane.name}: {line}'
            if text not in compromises:
                compromises.append(text)
        record = {'key': lane.key, 'kind': lane.kind, 'philosophy_id': lane.philosophy_id,
                  'track_id': lane.track_id, 'name': lane.name, 'weight': round(lane.weight, 4),
                  'days': lane.days, 'reserved_days': list(lane.reserved),
                  'cuts': {**lane.cuts, 'exposures': {k: v for k, v in lane.cuts['exposures'].items() if v}}}
        if lane.kind == 'contract':
            record['training_contract'] = {**program.get('training_contract', {}),
                                           'volume_scale': lane.cuts['volume'],
                                           'exposure_cuts': {k: v for k, v in lane.cuts['exposures'].items() if v},
                                           'optional_dropped': lane.cuts['optional']}
            record['module_state'] = program.get('module_state')
        composition_lanes.append(record)
        if program.get('coverage_report'):
            reports.append(program['coverage_report'])
    coverage = {'philosophy': lead.philosophy_id, 'strict': all(r.get('strict') for r in reports)}
    for key in ('unfilled_sessions', 'unfilled_slots', 'borrowed_sessions', 'substituted_sessions',
                'placed_tests', 'skipped_tests'):
        coverage[key] = [item for r in reports for item in r.get(key) or []]
    return {'weeks': out_weeks, 'compromises': compromises, 'coverage_report': coverage,
            'composition': {'lanes': composition_lanes, 'days': list(pool)}}


def _trace(lanes: list[Lane], result: dict, merged: dict) -> dict:
    """The Dev Lab's trace: the lead track's week shape, every track's sessions."""
    traces = {}
    for lane in lanes:
        program = result['programs'][lane.key]
        traces[lane.key] = (program.get('generation_trace') or {}).get('weeks') or []
    weeks = []
    for i, week in enumerate(merged['weeks']):
        lead = (traces[lanes[0].key][i:i + 1] or [{}])[0]
        sessions: dict = {}
        for lane in lanes:
            lane_week = (traces[lane.key][i:i + 1] or [{}])[0]
            for day, items in (lane_week.get('sessions') or {}).items():
                sessions.setdefault(day, []).extend({**t, 'lane_key': lane.key} for t in items)
        weeks.append({**lead, 'sessions': sessions, 'lanes': week['lanes']})
    return {'weeks': weeks, 'primary_sources': [l.philosophy_id for l in lanes],
            'philosophy_mode': 'composition',
            'lanes': [{k: v for k, v in l.items() if k != 'module_state'} for l in merged['composition']['lanes']]}


def generate(lanes: list[Lane], constraints: dict, *, num_weeks: int, first_week_number: int = 1,
             event_date=None, extra_injury_flags: dict | None = None, include_trace: bool = False) -> dict:
    """The composed program in the engine's result shape (as generator.generate
    returns), plus `composition`; a refusal returns `validation_errors`."""
    data = loader.load_all_data()
    frameworks = loader.load_all_frameworks()
    injury_flags = {**data['injury_flags'], **(extra_injury_flags or {})}
    for lane in lanes:
        lane.entries = _entries(lane, num_weeks, first_week_number, event_date)
    days = int(constraints.get('days_per_week', 4))
    lead_fw = frameworks.get(lanes[0].entries[0].get('framework_id')) or {}
    pool = _build_day_pool(days, sorted(constraints.get('preferred_days') or []),
                           sorted(constraints.get('forced_rest_days') or []),
                           framework_id=lead_fw.get('id', ''), phase=lanes[0].entries[0]['phase'],
                           week_in_phase=1, framework=lead_fw)
    cap = constraints.get('session_time_minutes', 60)
    configs = constraints.get('day_configs') or {}
    # A day's minutes are the athlete's for the day (a schedule's day total),
    # else one session's.
    day_cap = {d: (configs.get(d) or {}).get('minutes', cap) for d in pool}
    for lane, share in zip(lanes, split_days([l.weight for l in lanes], len(pool), [_floor(l) for l in lanes])):
        lane.days = share
    reserve_days(lanes, pool, frameworks)

    budget = {l.key: l.weight * sum(day_cap.values()) for l in lanes}
    blocked: set = set()
    history: list = []
    last: _Failed | None = None
    for _ in range(_MAX_CUTS + 1):
        try:
            result = _run_once(lanes, constraints, data, injury_flags, frameworks, pool, day_cap, include_trace)
            break
        except _Failed as failed:
            last = failed
            lane = failed.lane
            if failed.rules and lane.kind != 'contract':
                # A template none of whose days could be filled: give it
                # another day (the next of its week), else it cannot run.
                if lane.days < _template_days(lane):
                    lane.days += 1
                    reserve_days(lanes, pool, frameworks)
                    continue
                if _alone_error(lane, constraints, injury_flags):
                    return _refusal(lanes, failed, alone=True)
                # It runs alone: the other tracks leave it no room, so they give way.
            made = [h for h in history if h[0] is lane and h[1] != 'optional']
            if failed.rules and made:
                # A cut broke the track's own phase rules (a session its
                # phase requires, its ramp): undo the last one and never make
                # it again.
                _, kind, mid = made[-1]
                history.remove(made[-1])
                if kind == 'volume':
                    lane.cuts['volume'] = round(lane.cuts['volume'] / _VOLUME_STEP, 4)
                    blocked.add((lane.key, 'volume'))
                else:
                    lane.cuts['exposures'][mid] -= 1
                    blocked.add((lane.key, 'exposures', mid))
            # The track furthest over its share of the week's minutes gives
            # way first (the one that failed by what its week asked for),
            # with its cheapest cut.
            ratio = {l.key: failed.minutes.get(l.key, 0) / (budget[l.key] or 1) for l in lanes}
            candidates = sorted(lanes, key=lambda l: (-ratio[l.key], l.weight))
            lane, option = next(((l, o[0]) for l in candidates for o in [_cut_options(l, blocked, failed)] if o),
                                (None, None))
            if lane is None:
                return _refusal(lanes, failed, alone=failed.rules and bool(_alone_error(failed.lane, constraints,
                                                                                         injury_flags)))
            _, kind, mid = option
            history.append((lane, kind, mid))
            if kind == 'optional':
                lane.cuts['optional'] = True
            elif kind == 'volume':
                lane.cuts['volume'] = round(lane.cuts['volume'] * _VOLUME_STEP, 4)
            else:
                lane.cuts['exposures'][mid] = lane.cuts['exposures'].get(mid, 0) + 1
    else:
        return _refusal(lanes, last)
    merged = _merge(lanes, result, pool, day_cap)
    merged['compromises'] = _cuts_said(lanes) + merged['compromises']
    if include_trace:
        merged['generation_trace'] = _trace(lanes, result, merged)
    return merged


def _cuts_said(lanes: list[Lane]) -> list[str]:
    """Every cut the ladder made, one line each, naming the track."""
    out = []
    for lane in lanes:
        others = ' and '.join(l.name for l in lanes if l is not lane)
        for cut in ('optional', 'volume', 'exposures'):
            if (cut == 'optional' and lane.cuts['optional']) or (cut == 'volume' and lane.cuts['volume'] != 1.0) \
                    or (cut == 'exposures' and any(lane.cuts['exposures'].values())):
                out.append(_cut_text(lane, cut, others))
    return out


def _alone_error(lane: Lane, constraints: dict, injury_flags: dict) -> str | None:
    """Why the lane's track cannot run for this athlete even alone, if it
    cannot (CrossFit's named workouts for a novice): the composition is then
    not the cause, and the refusal says so."""
    from .generator import generate
    goal = {**lane.goal, **({'training_contract': lane.contract} if lane.contract else {})}
    # Alone on the days it asks for, not the whole week (the Texas Method
    # trains at most four).
    days = max(1, min(int(constraints.get('days_per_week', 4)), max(lane.days, _needed_days(lane))))
    alone = {k: v for k, v in constraints.items() if k not in ('module_progression_states', 'preferred_days')}
    result = generate(None, {**alone, 'days_per_week': days},
                      num_weeks=len(lane.entries) or 4, output_format='dict', goal_dict=goal,
                      extra_injury_flags=injury_flags, policy=lane.policy)
    errors = result.get('validation_errors') or []
    return '; '.join(e['message'] for e in errors) or None


def _refusal(lanes: list[Lane], failed: _Failed, alone: bool = False) -> dict:
    others = ' and '.join(l.name for l in lanes if l is not failed.lane)
    when = ''
    if failed.entry:
        phase = failed.entry.get('phase_name') or failed.entry.get('phase_id') or failed.entry.get('phase')
        when = f" in week {failed.entry.get('week_in_program')} ({phase})"
    # A track that cannot run for this athlete at all says so plainly; one
    # the others leave no room for says beside what.
    reason = str(failed.error)
    if not alone and failed.lane.kind != 'contract':
        reason = "none of its named workouts fits as written in the time the other tracks leave"
    message = (f"{failed.lane.name}: {failed.error}" if alone
               else f"{failed.lane.name} cannot fit beside {others}{when}: {reason}")
    return {'weeks': [], 'compromises': [], 'validation_errors': [{
        'code': 'COMPOSITION_UNFULFILLED',
        'message': message,
        'suggested_fix': 'Add a training day or minutes, lower its weight, or drop a track.'}]}


def lane_view(program: dict, key: str) -> dict:
    """The program as one track sees it: every other track's session keeps its
    place in its day (log keys count sessions by position) but carries no
    modules, so nothing of it is read as this track's work."""
    out = {k: v for k, v in program.items() if k != 'weeks'}
    lane = next((l for l in (program.get('composition') or {}).get('lanes') or [] if l.get('key') == key), {})
    out['training_contract'] = lane.get('training_contract')
    out['module_state'] = lane.get('module_state')
    weeks = []
    for week in program.get('weeks') or []:
        schedule = {}
        for day, sessions in (week.get('schedule') or {}).items():
            schedule[day] = [s if s.get('lane_key') == key else {k: v for k, v in s.items() if k != 'modules'}
                             for s in sessions]
        weeks.append({**week, 'schedule': schedule})
    out['weeks'] = weeks
    return out
