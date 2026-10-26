"""Does a generated program do what its methodology says?

`check_program` reads one generated program (the `generate(..., output_format=
'dict')` shape, integer day keys) against what the package declares. Most of
that is the phase's framework: `sessions_per_week`, `intensity_distribution`
and `deload_protocol`. The archetypes' `training_levels` and
`applicable_phases`, the modalities' recovery windows, and the athlete's
equipment and injury flags count too. On top of that comes the optional
`checks:` block a phase may carry in `philosophy.yaml`, which turns the
numbers in the phase's prose (a fixed 3x5, Zones 1-2 only, +10 % a week) into
something testable.

The generator never reads `checks:`. This module is a reader of the plan, not
a second engine. It is pure (no I/O, no generation) so `test_fidelity.py`
can pin each rule on hand-built weeks, and `tools/check_fidelity.py` runs it
over every philosophy x track x phase x athlete profile.

Each finding carries a `key` that leaves out the week, so a baseline of known
findings stays stable while the program around it changes.
"""
from __future__ import annotations

from collections import Counter, defaultdict
from dataclasses import dataclass, field

from src import phases as phases_mod
from src.analytics.families import is_strength
from src.scheduler import consecutive_allowances
from src.selector import _equipment_ok, _injury_exclusions, _matches_slot_filter, is_main_lift_slot

BUCKETS = ('zone1_2_pct', 'zone3_pct', 'zone4_5_pct', 'max_effort_pct')

# Slot intensity words to a bucket, for slots whose load carries no zone band.
_INTENSITY_BUCKET = {
    'zone1': 'zone1_2_pct', 'zone2': 'zone1_2_pct', 'low': 'zone1_2_pct',
    'light': 'zone1_2_pct', 'bodyweight': 'zone1_2_pct',
    'zone3': 'zone3_pct', 'moderate': 'zone3_pct', 'medium': 'zone3_pct',
    'submaximal': 'zone3_pct', 'progressing': 'zone3_pct',
    'zone4': 'zone4_5_pct', 'zone4_5': 'zone4_5_pct', 'zone5': 'zone4_5_pct',
    'high': 'zone4_5_pct',
    'heavy': 'max_effort_pct', 'max': 'max_effort_pct', 'max_effort': 'max_effort_pct',
}
_BUCKET_RANK = {b: i for i, b in enumerate(BUCKETS)}


SHAPE_TOLERANCE = 0.15
INTENSITY_TOLERANCE = 0.15
DELOAD_TOLERANCE = 0.20


@dataclass
class Finding:
    rule: str
    severity: str            # 'error' | 'warn' | 'info'
    phase_id: str | None
    subject: str             # what the finding is about: a modality, archetype, exercise, bucket
    detail: str
    weeks: list = field(default_factory=list)

    @property
    def key(self) -> str:
        return f"{self.phase_id}|{self.rule}|{self.subject}"

    def as_dict(self) -> dict:
        return {'rule': self.rule, 'severity': self.severity, 'phase_id': self.phase_id,
                'subject': self.subject, 'detail': self.detail, 'weeks': self.weeks,
                'key': self.key}


# ---------------------------------------------------------------------------
# Reading a session
# ---------------------------------------------------------------------------

def _work(session: dict) -> list:
    """Exercise assignments that are work: not meta rows."""
    return [ea for ea in session.get('exercises') or [] if not ea.get('meta')]


def _slot_minutes(ea: dict) -> float:
    """A timed slot's minutes: a duration, or an AMRAP / EMOM's time."""
    load = ea.get('load') or {}
    return float(load.get('duration_minutes') or load.get('time_minutes') or 0)


def _timed_rows(session: dict) -> list:
    """Rows that carry minutes, including meta rows (a BJJ class is its blocks)."""
    return [ea for ea in session.get('exercises') or []
            if _slot_minutes(ea) and (ea.get('exercise') or ea.get('meta'))]


def session_minutes(session: dict) -> float:
    """Planned minutes for one session.

    Timed slots carry `load.duration_minutes` (an AMRAP or EMOM its
    `time_minutes`); a session made only of timed slots is their sum. A
    session with set-and-rep work in it is at least its archetype's estimate.
    `api._week_volume` uses the timed sum whenever it is non-zero, which turns
    a 60-minute strength session with a 10-minute warm-up into 10 minutes.
    """
    timed = sum(_slot_minutes(ea) for ea in _timed_rows(session))
    untimed = any(ea.get('exercise') and not _slot_minutes(ea) and
                  (ea.get('slot') or {}).get('slot_type', ea.get('slot_type')) != 'amrap_movement'
                  for ea in _work(session))
    est = float(((session.get('archetype') or {}).get('duration_estimate_minutes')) or 0)
    if timed and not untimed:
        return timed
    return max(timed, est)


def _zone_bucket(zone: int) -> str:
    return 'zone1_2_pct' if zone <= 2 else ('zone3_pct' if zone == 3 else 'zone4_5_pct')


def _slot_split(ea: dict) -> dict | None:
    """{bucket: share} for one slot.

    A zone band spreads evenly over its zones, so a Zone 2-4 progression is a
    third easy, a third threshold and a third hard. Without a band the slot's
    intensity word decides; heavy work inside a conditioning session is hard
    conditioning, not max-effort lifting.
    """
    load = ea.get('load') or {}
    lo, hi = load.get('zone_lower'), load.get('zone_upper')
    if isinstance(hi, (int, float)):
        lo = int(lo if isinstance(lo, (int, float)) else hi)
        zones = list(range(lo, int(hi) + 1)) or [int(hi)]
        out: dict = defaultdict(float)
        for z in zones:
            out[_zone_bucket(z)] += 1 / len(zones)
        return dict(out)
    word = ((ea.get('slot') or {}).get('intensity') or load.get('intensity') or '').lower()
    bucket = _INTENSITY_BUCKET.get(word)
    if bucket == 'max_effort_pct':
        bucket = 'zone4_5_pct'
    return {bucket: 1.0} if bucket else None


def session_buckets(session: dict) -> dict:
    """Planned minutes per intensity bucket.

    Strength-family work counts as max effort, the way the analytics
    `zone_minutes` primitive reads a completed one. Anything else is bucketed
    slot by slot: timed slots by their zone band, and the session's remaining
    minutes by its hardest untimed slot (zone 3 when nothing says).
    """
    total = session_minutes(session)
    out = dict.fromkeys(BUCKETS, 0.0)
    if is_strength(session.get('modality')):
        out['max_effort_pct'] = total
        return out
    timed = 0.0
    for ea in _timed_rows(session):
        mins = _slot_minutes(ea)
        for b, share in (_slot_split(ea) or {'zone3_pct': 1.0}).items():
            out[b] += mins * share
        timed += mins
    hardest = None
    for ea in _work(session):
        if not ea.get('exercise') or _slot_minutes(ea):
            continue
        split = _slot_split(ea) or {}
        for b in split:
            if hardest is None or _BUCKET_RANK[b] > _BUCKET_RANK[hardest]:
                hardest = b
    rest = total - timed
    if rest > 0:
        out[hardest or 'zone3_pct'] += rest
    return out


def _sessions(week: dict):
    for day, sessions in sorted((week.get('schedule') or {}).items(), key=lambda kv: _day_num(kv[0])):
        for s in sessions:
            yield _day_num(day), s


_DAY_NAMES = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']


def _day_num(day) -> int:
    if isinstance(day, int):
        return day
    if isinstance(day, str) and day.isdigit():
        return int(day)
    return _DAY_NAMES.index(day) + 1 if day in _DAY_NAMES else 0


def _counted_minutes(s: dict) -> float:
    """A session's planned minutes — a test's are the session it stands in for
    (`test.instead_of`, src/generator._stand_in): a test runs as written
    whatever the week, and would read as a deload that did not deload."""
    if s.get('test'):
        return float(((s['test'].get('instead_of') or {}).get('minutes')) or 0)
    return session_minutes(s)


def _counted_buckets(s: dict) -> dict:
    """Minutes per intensity bucket — a test's are the session it stands in for."""
    if s.get('test'):
        return dict((s['test'].get('instead_of') or {}).get('buckets') or {})
    return session_buckets(s)


def week_minutes(week: dict) -> float:
    return sum(_counted_minutes(s) for _, s in _sessions(week))


# ---------------------------------------------------------------------------
# The check
# ---------------------------------------------------------------------------

class _Collector:
    """Findings keyed by (phase, rule, subject); repeated weeks fold into one."""

    def __init__(self):
        self._by_key: dict[str, Finding] = {}

    def add(self, rule, severity, phase_id, subject, detail, week=None):
        f = Finding(rule, severity, phase_id, str(subject), detail)
        existing = self._by_key.get(f.key)
        if existing is None:
            self._by_key[f.key] = existing = f
        if week is not None and week not in existing.weeks:
            existing.weeks.append(week)

    def findings(self) -> list[Finding]:
        order = {'error': 0, 'warn': 1, 'info': 2}
        return sorted(self._by_key.values(), key=lambda f: (order[f.severity], f.phase_id or '', f.rule, f.subject))


def _phase_groups(weeks: list) -> list[tuple[str, list]]:
    """Consecutive weeks grouped by phase id, in program order."""
    groups: list[tuple[str, list]] = []
    for w in weeks:
        pid = w.get('phase_id') or w.get('phase')
        if groups and groups[-1][0] == pid:
            groups[-1][1].append(w)
        else:
            groups.append((pid, [w]))
    return groups


def check_program(program: dict, philosophy: dict, track: dict, constraints: dict,
                  frameworks: dict, library: dict) -> list[Finding]:
    """Every rule, over one generated program.

    `library` is `loader.load_all_data()` (or the policy-scoped copy): it
    supplies modalities, injury flags and exercises by id.
    """
    out = _Collector()
    phase_by_id = {p['id']: p for p in track.get('phases') or []}
    for phase_id, pweeks in _phase_groups(program.get('weeks') or []):
        _check_claims(out, phase_id, pweeks, (phase_by_id.get(phase_id) or {}).get('checks') or {})
    equipment = set(constraints.get('equipment') or [])
    injury_flags = library.get('injury_flags') or {}
    excl_patterns, excl_ids = _injury_exclusions(constraints, injury_flags)
    flagged = set(constraints.get('injury_flags') or [])
    if program.get('training_contract'):
        from . import training_contract
        try:
            contract = training_contract.load_contract(philosophy['id'], track['id'])
            if contract is None:
                raise training_contract.ContractError('The generated program names no installed contract.')
            training_contract.verify(program, contract, constraints)
            training_contract.verify_phase_rules(program, {'phase_sequence': phases_mod.phase_sequence_for(track)})
        except training_contract.ContractError as exc:
            out.add('training_contract', 'error', None, track['id'], str(exc))
        # The contract agrees with itself; the athlete's equipment and
        # injuries are still the athlete's.
        for phase_id, pweeks in _phase_groups(program.get('weeks') or []):
            for w in pweeks:
                for _, s in _sessions(w):
                    for ea in _work(s):
                        if ea.get('exercise'):
                            _check_compliance(out, phase_id, w.get('week_number'), ea, equipment,
                                              excl_patterns, excl_ids, flagged)
        return out.findings()
    weeks = program.get('weeks') or []
    modalities = library.get('modalities') or {}
    level = constraints.get('training_level', 'intermediate')

    prev_phase_tail_minutes = None
    for phase_id, pweeks in _phase_groups(weeks):
        phase = phase_by_id.get(phase_id, {})
        checks = phase.get('checks') or {}
        fw_id = phase.get('framework_id') or pweeks[0].get('framework')
        fw = frameworks.get(fw_id) or {}
        kind = pweeks[0].get('phase')
        # A taper flags every week a deload; its weeks are still the phase.
        work_weeks = [w for w in pweeks if not w.get('is_deload')] or pweeks

        for w in pweeks:
            wn = w.get('week_number')
            if phase.get('framework_id') and w.get('framework') != phase['framework_id']:
                out.add('framework_mismatch', 'error', phase_id, w.get('framework'),
                        f"week ran {w.get('framework')}, the phase names {phase['framework_id']}", wn)
            _check_week(out, w, phase_id, kind, fw, level, equipment, excl_patterns, excl_ids,
                        flagged, injury_flags, modalities, library, constraints,
                        {**checks, 'exclude_exercises': phase.get('exclude_exercises')},
                        templated=bool(phase.get('week_templates')))

        if phase.get('week_templates'):
            # The source writes the week day by day; that is its shape.
            _check_template(out, phase_id, phase, fw, pweeks, constraints)
        else:
            _check_shape(out, phase_id, fw, work_weeks, philosophy)
        _check_intensity(out, phase_id, fw, work_weeks, checks)
        _check_deload(out, phase_id, fw, pweeks, constraints)
        _check_required(out, phase_id, work_weeks, checks)
        _check_fixed(out, phase_id, pweeks, modalities, not phase.get('rotate_main_lifts'))
        _check_volume(out, phase_id, work_weeks, checks, prev_phase_tail_minutes)
        _check_tests(out, phase_id, phase, pweeks)
        if work_weeks:
            prev_phase_tail_minutes = week_minutes(work_weeks[-1])
    return out.findings()


def _check_week(out, w, phase_id, kind, fw, level, equipment, excl_patterns, excl_ids,
                flagged, injury_flags, modalities, library, constraints, checks, templated=False):
    wn = w.get('week_number')
    allowed = consecutive_allowances(fw, kind)
    max_zone = checks.get('max_zone')
    forbidden = set(checks.get('archetypes_forbidden') or [])
    forbidden_ex = set(checks.get('exclude_exercises') or [])
    placed: dict[int, list[str]] = defaultdict(list)
    session_cap = constraints.get('session_time_minutes')

    for day, s in _sessions(w):
        mod = s.get('modality')
        placed[day].append(mod)
        arch = s.get('archetype')
        if not arch:
            out.add('session_without_archetype', 'error', phase_id, mod,
                    f"a {mod} session has no archetype", wn)
            continue
        aid = arch.get('id')
        if aid in forbidden:
            out.add('archetype_forbidden', 'error', phase_id, aid,
                    f"{arch.get('name', aid)} is ruled out for this phase", wn)
        levels = arch.get('training_levels')
        if levels and level not in levels:
            out.add('level_mismatch', 'error', phase_id, aid,
                    f"{aid} is for {levels}, the athlete is {level}", wn)
        elif not levels:
            out.add('level_undeclared', 'info', phase_id, aid,
                    f"{aid} declares no training_levels, so every level gets it", wn)
        kinds = arch.get('applicable_phases') or []
        if kinds and kind not in kinds:
            out.add('phase_kind_mismatch', 'error', phase_id, aid,
                    f"{aid} applies to {kinds}, the week is {kind}", wn)
        if session_cap and (arch.get('duration_estimate_minutes') or 0) > session_cap * 1.1 \
                and not (arch.get('scaling') or {}).get('time_limited'):
            out.add('session_over_time', 'warn', phase_id, aid,
                    f"{aid} runs {arch.get('duration_estimate_minutes')} min against a "
                    f"{session_cap}-min session", wn)

        in_session = {(ea.get('exercise') or {}).get('id') for ea in _work(s)} - {None}
        for ea in _work(s):
            ex = ea.get('exercise')
            if ex is None:
                if ea.get('equipment_gap') or ea.get('gap_reason') == 'LEVEL_LOCKED':
                    out.add('equipment_gap' if ea.get('equipment_gap') else 'level_gap', 'info',
                            phase_id, f"{aid}:{ea.get('slot_role')}",
                            f"{aid} slot '{ea.get('slot_role')}' is empty: {ea.get('error')}", wn)
                elif not ea.get('injury_skip') and not ea.get('coverage_gap'):
                    out.add('silent_empty_slot', 'error', phase_id, f"{aid}:{ea.get('slot_role')}",
                            f"{aid} slot '{ea.get('slot_role')}' is empty with no reason given", wn)
                elif ea.get('injury_skip'):
                    sub = _available_substitute(ea, flagged, injury_flags, library, equipment,
                                                excl_patterns, excl_ids, in_session)
                    if sub:
                        out.add('injury_substitute_unused', 'warn', phase_id,
                                f"{aid}:{ea.get('slot_role')}",
                                f"{aid} slot '{ea.get('slot_role')}' was skipped for an injury; "
                                f"the flag names {sub} as the substitute", wn)
                    else:
                        out.add('injury_skip', 'info', phase_id, f"{aid}:{ea.get('slot_role')}",
                                f"{aid} slot '{ea.get('slot_role')}' skipped for an injury", wn)
                continue
            eid = ex.get('id')
            if eid in forbidden_ex:
                out.add('exercise_forbidden', 'error', phase_id, eid,
                        f"{eid} is ruled out for this phase", wn)
            _check_compliance(out, phase_id, wn, ea, equipment, excl_patterns, excl_ids, flagged)
            if max_zone and not is_strength(mod):
                hi = (ea.get('load') or {}).get('zone_upper')
                if isinstance(hi, (int, float)) and hi > max_zone:
                    out.add('zone_above_cap', 'error', phase_id, f"{aid}:{eid}",
                            f"{eid} in {aid} reaches Zone {hi}; the phase caps at Zone {max_zone}", wn)

    if not templated:
        # A templated week's day order is the source's own.
        _check_recovery(out, phase_id, wn, placed, modalities, allowed)
    _read_regions(out, phase_id, wn, w, modalities)


def _read_regions(out, phase_id, wn, w, modalities):
    """Information, never drift: a body region two sessions a day apart both
    load heavily (src/recovery_regions.py). A source may mean it — a source's
    own week is never rearranged for it — so it is read, not gated."""
    from . import recovery_regions
    heavy: dict[int, frozenset] = defaultdict(frozenset)
    for day, s in _sessions(w):
        heavy[day] |= recovery_regions.heavy(recovery_regions.session_load(s, modalities))
    for day in sorted(heavy):
        for region in sorted(heavy[day] & heavy.get(day + 1, frozenset())):
            out.add('region_back_to_back', 'info', phase_id, region,
                    f"{region.replace('_', ' ')} loaded heavily on {_DAY_NAMES[day - 1]} and {_DAY_NAMES[day]}", wn)


def _check_compliance(out, phase_id, wn, ea, equipment, excl_patterns, excl_ids, flagged):
    """A prescribed exercise the athlete's equipment or injuries rule out."""
    ex = ea['exercise']
    eid = ex.get('id')
    if not _equipment_ok(ex, equipment):
        out.add('equipment_violation', 'error', phase_id, eid,
                f"{eid} needs {sorted(set(ex.get('equipment', [])) - equipment - {'open_space', 'none'})}", wn)
    if not ea.get('substituted_for') and (
            eid in excl_ids or set(ex.get('movement_patterns') or []) & excl_patterns
            or set(ex.get('contraindicated_with') or []) & flagged):
        out.add('injury_violation', 'error', phase_id, eid,
                f"{eid} is excluded or contraindicated by {sorted(flagged)}", wn)


def _check_template(out, phase_id, phase, fw, pweeks, constraints):
    """A templated phase runs the source's week: each day the athlete keeps,
    in its category (a test stands in for the day it replaces). A day left
    out or run as its declared fallback is the athlete's equipment, injuries
    or time, which the week's compromises name — information, not drift."""
    from . import week_template
    categories = fw.get('categories') or {}
    templates = phase['week_templates']
    for w in pweeks:
        wn = w.get('week_number')
        template = templates[((w.get('week_in_phase') or 1) - 1) % len(templates)]
        kept, _ = week_template.training_days(template, constraints.get('days_per_week', 6),
                                              phase.get('drop_order') or [], categories)
        want = Counter(spec['categories'][0] for _, spec in kept)
        got = Counter(s.get('category') for _, s in _sessions(w))
        for cat, n in (want - got).items():
            out.add('template_day_missing', 'info', phase_id, cat,
                    f"{n} {categories.get(cat, {}).get('name', cat)} day(s) of the source's week "
                    'did not run (see the compromises)', wn)
        for cat, n in (got - want).items():
            if cat not in categories:
                out.add('template_foreign_day', 'error', phase_id, str(cat),
                        f"a session outside the phase's day categories ({cat})", wn)
            else:
                out.add('template_fallback', 'info', phase_id, cat,
                        f"{n} day(s) ran as {categories[cat]['name']} in place of the written category", wn)


def _check_recovery(out, phase_id, wn, placed: dict, modalities: dict, allowed: frozenset):
    days = sorted(placed)
    for i, d1 in enumerate(days):
        for d2 in days[i + 1:]:
            hours = (d2 - d1) * 24
            if hours >= 72:
                break
            for m1 in placed[d1]:
                for m2 in placed[d2]:
                    if hours <= 24 and frozenset((m1, m2)) in allowed:
                        continue
                    need = (modalities.get(m2) or {}).get('recovery_hours_min', 24)
                    both_high = all((modalities.get(m) or {}).get('recovery_cost') == 'high'
                                    for m in (m1, m2))
                    if m1 == m2 and hours < need:
                        out.add('recovery_window', 'warn', phase_id, m2,
                                f"{m2} repeats after {hours} h; it needs {need} h", wn)
                    elif m1 != m2 and both_high and hours < 48:
                        out.add('recovery_window', 'warn', phase_id, f"{m1}+{m2}",
                                f"{m1} and {m2} are both high-cost, {hours} h apart", wn)


def _available_substitute(ea, flagged, injury_flags, library, equipment, excl_patterns, excl_ids,
                          in_session=frozenset()):
    """The flag's own `modified_exercises` substitute that would fill this slot:
    an entry whose `instead_of` fits the slot and whose `use` is in the
    library, unexcluded and within the athlete's equipment (the rule
    `selector._explain_unfilled` applies, short of the level check): not
    already in the session, not contraindicated by a flag, clear of every
    other flag's excluded patterns."""
    exercises = library.get('exercises') or {}
    ex_filter = (ea.get('slot') or {}).get('exercise_filter') or {}
    for fid in flagged:
        for mod in (injury_flags.get(fid) or {}).get('modified_exercises') or []:
            was, use = exercises.get(mod.get('instead_of')), exercises.get(mod.get('use'))
            if not was or not use or use['id'] in excl_ids or not _equipment_ok(use, equipment):
                continue
            others = {pat for f in flagged if f != fid
                      for pat in (injury_flags.get(f) or {}).get('excluded_movement_patterns') or []}
            if use['id'] in in_session or set(use.get('movement_patterns') or []) & others \
                    or set(use.get('contraindicated_with') or []) & set(flagged):
                continue
            if _matches_slot_filter(was, ex_filter, set()):
                return use['id']
    return None


def _check_shape(out, phase_id, fw, work_weeks, philosophy):
    declared = {m: float(n) for m, n in (fw.get('sessions_per_week') or {}).items() if n}
    if not declared or not work_weeks:
        return
    total_declared = sum(declared.values())
    counts: Counter = Counter()
    n_sessions = 0
    for w in work_weeks:
        for _, s in _sessions(w):
            # A test counts as the session it stands in for.
            counts[(s.get('test') or {}).get('in_place_of') or s.get('modality')] += 1
            n_sessions += 1
    if not n_sessions:
        out.add('empty_phase', 'error', phase_id, fw.get('id'), "no sessions in any working week")
        return
    per_week = n_sessions / len(work_weeks)
    avoid = set(philosophy.get('avoid_with') or [])
    for mod, n in declared.items():
        want = n / total_declared
        got = counts.get(mod, 0) / n_sessions
        if counts.get(mod, 0) == 0 and want * per_week >= 0.75:
            out.add('modality_missing', 'error', phase_id, mod,
                    f"{fw.get('id')} calls for {n:g}/week of {mod}; none were scheduled")
        elif abs(got - want) > SHAPE_TOLERANCE:
            out.add('shape_drift', 'warn', phase_id, mod,
                    f"{mod} is {got:.0%} of sessions, {fw.get('id')} declares {want:.0%}")
    for mod, n in counts.items():
        if mod in declared:
            continue
        sev, rule = ('error', 'avoid_with') if mod in avoid else ('warn', 'modality_foreign')
        out.add(rule, sev, phase_id, mod,
                f"{mod} ({n} sessions) is not in {fw.get('id')}'s sessions_per_week"
                + (" and the philosophy avoids it" if mod in avoid else ''))


def _check_intensity(out, phase_id, fw, work_weeks, checks):
    """Planned minutes per bucket against `intensity_distribution`.

    A distribution with no max-effort share describes the conditioning only
    (Uphill's strength days sit outside its 90/10), so strength-family
    sessions are left out of both sides.
    """
    dist = fw.get('intensity_distribution') or {}
    if not dist or not work_weeks:
        return
    include_strength = float(dist.get('max_effort_pct') or 0) > 0
    totals = dict.fromkeys(BUCKETS, 0.0)
    for w in work_weeks:
        for _, s in _sessions(w):
            # A test counts as the session it stands in for, as in the shape.
            modality = (s.get('test') or {}).get('in_place_of') or s.get('modality')
            if not include_strength and is_strength(modality):
                continue
            for b, m in _counted_buckets(s).items():
                totals[b] += m
    grand = sum(totals.values())
    if grand <= 0:
        return
    tol = float(checks.get('intensity_split_tolerance', INTENSITY_TOLERANCE))
    for b in BUCKETS:
        want = float(dist.get(b) or 0)
        got = totals[b] / grand
        if abs(got - want) > tol:
            out.add('intensity_split', 'warn', phase_id, b,
                    f"{b.replace('_pct', '')} is {got:.0%} of planned minutes, "
                    f"{fw.get('id')} declares {want:.0%}")


def _check_deload(out, phase_id, fw, pweeks, constraints):
    proto = fw.get('deload_protocol') or {}
    overreached = constraints.get('fatigue_state') == 'overreached'
    freq = proto.get('frequency_weeks')
    keep = proto.get('volume_reduction_pct')
    kind_deload = pweeks and phases_mod.kind_flag(pweeks[0].get('phase'), 'counts_as_deload')
    for i, w in enumerate(pweeks):
        if not w.get('is_deload'):
            continue
        wn = w.get('week_number')
        if not proto and not overreached:
            out.add('deload_without_protocol', 'warn', phase_id, fw.get('id'),
                    f"{fw.get('id')} declares no deload_protocol, yet the week is a deload", wn)
            continue
        prev = next((p for p in reversed(pweeks[:i]) if not p.get('is_deload')), None)
        if keep is None or prev is None or kind_deload:
            continue
        before, now = week_minutes(prev), week_minutes(w)
        if before > 0:
            ratio = now / before
            if abs(ratio - float(keep)) > DELOAD_TOLERANCE:
                out.add('deload_size', 'warn', phase_id, fw.get('id'),
                        f"deload keeps {ratio:.0%} of the previous week's minutes; "
                        f"{fw.get('id')} declares {float(keep):.0%}", wn)
    if freq and not overreached and not kind_deload and len(pweeks) >= freq \
            and not any(w.get('is_deload') for w in pweeks):
        out.add('deload_missing', 'warn', phase_id, fw.get('id'),
                f"{len(pweeks)} weeks with no deload; {fw.get('id')} deloads every {freq}")


def _check_required(out, phase_id, work_weeks, checks):
    # A week that tests is a test week: the test stands in for a session the
    # phase would otherwise require.
    work_weeks = [w for w in work_weeks if not any(s.get('test') for _, s in _sessions(w))]
    for aid in checks.get('archetypes_required') or []:
        for w in work_weeks:
            if not any((s.get('archetype') or {}).get('id') == aid for _, s in _sessions(w)):
                out.add('archetype_required', 'error', phase_id, aid,
                        f"{aid} is missing from a week the phase requires it in", w.get('week_number'))
    for mod in checks.get('modalities_required') or []:
        for w in work_weeks:
            if not any(s.get('modality') == mod for _, s in _sessions(w)):
                out.add('modality_required', 'error', phase_id, mod,
                        f"no {mod} session in a week the phase requires one", w.get('week_number'))


def claim_violations(pweeks: list, checks: dict) -> list[tuple[str, str, str, int | None]]:
    """The phase's defining claims (`checks:`) a generated phase breaks, as
    (rule, subject, detail, week number). Shared by the fidelity gate and the
    training contract's acceptance check (`training_contract.verify_phase_rules`),
    so a contract program cannot be saved breaking what the gate would flag.

    - `max_substituted_share`: sessions swapped to another modality because
      nothing of theirs fitted (`substituted_for`), as a share of the phase's.
    - `modality_outnumbers: [[a, b], ...]`: every non-deload week has more `a`
      sessions than `b` (BJJ's mat time over its strength work).
    - `max_archetype_share`: no archetype takes more than this share of its
      modality's sessions in the phase, once the modality has four or more.
    - `min_distinct_archetypes: {weeks, count, modality?}`: every run of that
      many weeks has at least `count` distinct archetypes (of the modality).
    """
    out = []
    sessions = [(w, s) for w in pweeks for _, s in _sessions(w) if not s.get('test')]
    share = checks.get('max_substituted_share')
    if share is not None and sessions:
        swapped = [s for _, s in sessions if s.get('substituted_for')]
        if len(swapped) / len(sessions) > share + 1e-9:
            out.append(('substituted_share', 'sessions',
                        f"{len(swapped)} of {len(sessions)} sessions are another modality's "
                        f"(at most {share:.0%})", None))
    for a, b in checks.get('modality_outnumbers') or []:
        for w in pweeks:
            if w.get('is_deload'):
                continue
            mods = [s.get('modality') for _, s in _sessions(w)]
            if mods.count(a) + mods.count(b) and mods.count(a) <= mods.count(b):
                out.append(('modality_outnumbers', f"{a}>{b}",
                            f"{mods.count(a)} {a} against {mods.count(b)} {b}", w.get('week_number')))
    cap = checks.get('max_archetype_share')
    if cap is not None:
        for mod, aid, top, total in archetype_shares(pweeks):
            if top / total > cap + 1e-9:
                out.append(('archetype_share', f"{mod}:{aid}",
                            f"{aid} is {top} of {total} {mod} sessions (at most {cap:.0%})", None))
    spec = checks.get('min_distinct_archetypes')
    if spec:
        size = min(int(spec['weeks']), len(pweeks))
        for i in range(len(pweeks) - size + 1):
            window = pweeks[i:i + size]
            ids = {(s.get('archetype') or {}).get('id') for w in window for _, s in _sessions(w)
                   if not s.get('test') and (not spec.get('modality') or s.get('modality') == spec['modality'])}
            if len(ids) < spec['count']:
                out.append(('distinct_archetypes', spec.get('modality') or 'sessions',
                            f"{len(ids)} distinct archetypes in {size} weeks (at least {spec['count']})",
                            window[0].get('week_number')))
    return out


def archetype_shares(pweeks: list, min_sessions: int = 4) -> list[tuple[str, str, int, int]]:
    """(modality, its most used archetype, that archetype's sessions, the
    modality's sessions) for each modality with `min_sessions` or more in the
    phase, tests aside. `max_archetype_share` and the scorecard's E4 read it."""
    by_mod: dict = defaultdict(Counter)
    for w in pweeks:
        for _, s in _sessions(w):
            if not s.get('test'):
                by_mod[s.get('modality')][(s.get('archetype') or {}).get('id')] += 1
    out = []
    for mod, counts in by_mod.items():
        total = sum(counts.values())
        if total >= min_sessions:
            aid, top = counts.most_common(1)[0]
            out.append((mod, aid, top, total))
    return out


def _check_claims(out, phase_id, pweeks, checks):
    for rule, subject, detail, week in claim_violations(pweeks, checks):
        out.add(rule, 'error', phase_id, subject, detail, week)


def _check_fixed(out, phase_id, pweeks, modalities, fixed: bool):
    """A loaded main lift keeps its exercise across the phase.

    The slot is identified by (archetype, slot index); `selector.is_main_lift_slot`
    says which slots are main lifts, in linear-load modalities only. A phase
    that sets `rotate_main_lifts` (CrossFit) is exempt.
    """
    if not fixed:
        return
    seen: dict[tuple, list] = defaultdict(list)
    for w in pweeks:
        for _, s in _sessions(w):
            if s.get('test') or (modalities.get(s.get('modality')) or {}).get('progression_model', 'linear_load') != 'linear_load':
                continue
            aid = (s.get('archetype') or {}).get('id')
            for ea in _work(s):
                slot = ea.get('slot') or {}
                if ea.get('exercise') and is_main_lift_slot(slot):
                    seen[(aid, ea.get('slot_index'), ea.get('slot_role'))].append(ea['exercise']['id'])
    for (aid, _, role), ids in seen.items():
        distinct = list(dict.fromkeys(ids))
        if len(distinct) > 1:
            out.add('main_lift_rotates', 'error', phase_id, f"{aid}:{role}",
                    f"{aid} '{role}' rotates {', '.join(distinct)} across the phase; "
                    f"a loaded main lift should keep its exercise")


def _check_volume(out, phase_id, work_weeks, checks, prev_tail):
    band = checks.get('volume_change_per_week')
    mins = [week_minutes(w) for w in work_weeks]
    if band and len(mins) > 1:
        lo, hi = band
        for prev, cur, pw, w in zip(mins, mins[1:], work_weeks, work_weeks[1:]):
            # Only adjacent weeks: the week after a deload restarts the ramp.
            if prev <= 0 or (w.get('week_number') or 0) - (pw.get('week_number') or 0) != 1:
                continue
            change = cur / prev - 1
            if change < lo - 1e-9 or change > hi + 1e-9:
                out.add('volume_ramp', 'warn', phase_id, 'minutes',
                        f"planned minutes change {change:+.0%} week to week; "
                        f"the phase calls for {lo:+.0%} to {hi:+.0%}", w.get('week_number'))
    band = checks.get('volume_vs_previous_phase')
    if band and prev_tail and mins:
        lo, hi = band
        change = (sum(mins) / len(mins)) / prev_tail - 1
        if change < lo - 1e-9 or change > hi + 1e-9:
            out.add('volume_vs_previous_phase', 'warn', phase_id, 'minutes',
                    f"mean weekly minutes {change:+.0%} against the previous phase; "
                    f"the phase calls for {lo:+.0%} to {hi:+.0%}")


# Why a declared test was not run: the athlete's circumstances (fine, said
# once) or the package's authoring (a test that can never be placed).
_ATHLETE_SKIPS = {'level', 'equipment_gap', 'injury_skip', 'session_too_short', 'overreached', 'deload'}


def _check_tests(out, phase_id, phase, pweeks):
    """Every test the phase declares is in its week — run, or skipped with a
    reason — no other week tests, and a test's scored slots are prescribed as
    written (src/standard_tests.protocol_load)."""
    from src import standard_tests
    declared = phase.get('tests') or []
    for w in pweeks:
        wn = w.get('week_number')
        entry = {'tests': declared, 'phase_weeks': phase.get('weeks') or 1,
                 'repeatable': phase.get('repeatable'), 'week_in_phase': w.get('week_in_phase')}
        expected = len(standard_tests.tests_for_week(entry)) if declared else 0
        placed = [s for _, s in _sessions(w) if s.get('test')]
        skipped = w.get('tests_skipped') or []
        if len(placed) + len(skipped) < expected:
            out.add('test_missing', 'error', phase_id, 'tests',
                    f"week {w.get('week_in_phase')} of the phase should test; it neither tests nor says why not", wn)
        if len(placed) > expected:
            out.add('test_unexpected', 'error', phase_id, (placed[0].get('test') or {}).get('archetype'),
                    f"a test in week {w.get('week_in_phase')}, where the phase declares none", wn)
        for t in skipped:
            reason = t.get('reason')
            subject = ','.join(t.get('archetypes') or [])
            if reason in _ATHLETE_SKIPS:
                out.add('test_skipped', 'info', phase_id, subject, f"test skipped: {reason}", wn)
            else:
                out.add('test_unplaceable', 'error', phase_id, subject,
                        f"the phase's test cannot be placed: {reason}", wn)
        for s in placed:
            for ea in _work(s):
                if ea.get('standard') and ea.get('exercise') and not (ea.get('load') or {}).get('test'):
                    out.add('test_scaled', 'error', phase_id, (s.get('test') or {}).get('archetype'),
                            f"{ea.get('slot_role')} measures {ea['standard'].get('id')} but is not "
                            f"prescribed as the test", wn)

