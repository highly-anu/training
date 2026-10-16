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


def week_minutes(week: dict) -> float:
    return sum(session_minutes(s) for _, s in _sessions(week))


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
    weeks = program.get('weeks') or []
    phase_by_id = {p['id']: p for p in track.get('phases') or []}
    modalities = library.get('modalities') or {}
    level = constraints.get('training_level', 'intermediate')
    equipment = set(constraints.get('equipment') or [])
    injury_flags = library.get('injury_flags') or {}
    excl_patterns, excl_ids = _injury_exclusions(constraints, injury_flags)
    flagged = set(constraints.get('injury_flags') or [])

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
                        {**checks, 'exclude_exercises': phase.get('exclude_exercises')})

        _check_shape(out, phase_id, fw, work_weeks, philosophy)
        _check_intensity(out, phase_id, fw, work_weeks, checks)
        _check_deload(out, phase_id, fw, pweeks, constraints)
        _check_required(out, phase_id, work_weeks, checks)
        _check_fixed(out, phase_id, pweeks, modalities, not phase.get('rotate_main_lifts'))
        _check_volume(out, phase_id, work_weeks, checks, prev_phase_tail_minutes)
        if work_weeks:
            prev_phase_tail_minutes = week_minutes(work_weeks[-1])
    return out.findings()


def _check_week(out, w, phase_id, kind, fw, level, equipment, excl_patterns, excl_ids,
                flagged, injury_flags, modalities, library, constraints, checks):
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
                                                excl_patterns, excl_ids)
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
            if not _equipment_ok(ex, equipment):
                out.add('equipment_violation', 'error', phase_id, eid,
                        f"{eid} needs {sorted(set(ex.get('equipment', [])) - equipment - {'open_space', 'none'})}", wn)
            if not ea.get('substituted_for') and (
                    eid in excl_ids or set(ex.get('movement_patterns') or []) & excl_patterns
                    or set(ex.get('contraindicated_with') or []) & flagged):
                out.add('injury_violation', 'error', phase_id, eid,
                        f"{eid} is excluded or contraindicated by {sorted(flagged)}", wn)
            if max_zone and not is_strength(mod):
                hi = (ea.get('load') or {}).get('zone_upper')
                if isinstance(hi, (int, float)) and hi > max_zone:
                    out.add('zone_above_cap', 'error', phase_id, f"{aid}:{eid}",
                            f"{eid} in {aid} reaches Zone {hi}; the phase caps at Zone {max_zone}", wn)

    _check_recovery(out, phase_id, wn, placed, modalities, allowed)


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


def _available_substitute(ea, flagged, injury_flags, library, equipment, excl_patterns, excl_ids):
    """The flag's own `modified_exercises` substitute that would fill this slot:
    an entry whose `instead_of` fits the slot and whose `use` is in the
    library, unexcluded and within the athlete's equipment (the rule
    `selector._explain_unfilled` applies)."""
    exercises = library.get('exercises') or {}
    ex_filter = (ea.get('slot') or {}).get('exercise_filter') or {}
    for fid in flagged:
        for mod in (injury_flags.get(fid) or {}).get('modified_exercises') or []:
            was, use = exercises.get(mod.get('instead_of')), exercises.get(mod.get('use'))
            if not was or not use or use['id'] in excl_ids or not _equipment_ok(use, equipment):
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
            counts[s.get('modality')] += 1
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
            if not include_strength and is_strength(s.get('modality')):
                continue
            for b, m in session_buckets(s).items():
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
            if (modalities.get(s.get('modality')) or {}).get('progression_model', 'linear_load') != 'linear_load':
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
