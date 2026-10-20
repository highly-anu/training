"""Tracks, phases and phase kinds.

A philosophy declares one or more **tracks** (philosophy.yaml → `tracks`). A
track is one way of following the philosophy — a goal or a program shape — and
is an ordered list of the philosophy's own **phases**. Each phase names the
framework that builds its weeks and a **kind** from the shared vocabulary in
data/commons/phase_kinds.yaml.

The words an athlete reads about a phase (name, focus, description,
adaptations, intensity) come only from the package that owns it. The engine
never reads them; it reads the kind. This module is the one place both halves
meet, so the generator, the event-date calendar, the validator and the API
cannot disagree about what a phase is.
"""
from __future__ import annotations

from . import loader


class PhaseResolutionError(ValueError):
    """A track or start phase does not exist in the philosophy."""


# Display keys copied from a philosophy's phase onto the goal's phase_sequence.
_PHASE_TEXT_KEYS = ('name', 'focus', 'description', 'adaptations', 'intensity', 'repeatable')


# ---------------------------------------------------------------------------
# Kinds
# ---------------------------------------------------------------------------

def kinds() -> dict:
    return loader.load_phase_kinds()


def kind_flag(kind: str | None, flag: str) -> bool:
    return bool((kinds().get(kind or '') or {}).get(flag))


def volume_multiplier(kind: str | None) -> float:
    return float((kinds().get(kind or '') or {}).get('volume_multiplier', 1.0))


def deload_kinds() -> frozenset:
    return frozenset(k for k, v in kinds().items() if (v or {}).get('counts_as_deload'))


# ---------------------------------------------------------------------------
# Tracks on a philosophy
# ---------------------------------------------------------------------------

def tracks_of(phil: dict) -> list:
    return list(phil.get('tracks') or [])


def framework_ids_of(phil: dict) -> list:
    """Every framework a philosophy uses, in track/phase order, deduplicated."""
    seen: list = []
    for track in tracks_of(phil):
        for phase in track.get('phases') or []:
            fid = phase.get('framework_id')
            if fid and fid not in seen:
                seen.append(fid)
    return seen


def primary_track(phil: dict, level: str | None = None) -> dict | None:
    """The track a request that names none gets: the one `track_for_level`
    gives the athlete's level, else `primary_track_id`, else the first."""
    tracks = tracks_of(phil)
    wanted = (phil.get('track_for_level') or {}).get(level) or phil.get('primary_track_id')
    if wanted:
        for t in tracks:
            if t.get('id') == wanted:
                return t
    return tracks[0] if tracks else None


def find_track(phil: dict, track_id: str | None) -> dict | None:
    if not track_id:
        return None
    return next((t for t in tracks_of(phil) if t.get('id') == track_id), None)


def track_for_framework(phil: dict, framework_id: str | None) -> tuple[dict, dict] | None:
    """(track, first phase) that runs `framework_id`, primary track first.

    Maps the legacy request field `framework_id` — "build with this framework"
    from Explore, or an old client's style pick — onto the track model, so an
    explicit pick starts the track at the phase that uses it instead of being
    overridden by the phase's own framework.
    """
    if not framework_id:
        return None
    tracks = tracks_of(phil)
    primary = primary_track(phil)
    ordered = ([primary] if primary else []) + [t for t in tracks if t is not primary]
    for track in ordered:
        for phase in track.get('phases') or []:
            if phase.get('framework_id') == framework_id:
                return track, phase
    return None


def validate_philosophy_tracks(phil: dict, framework_ids: set | None = None) -> list[str]:
    """Problems with a philosophy's tracks, as readable strings (empty = fine).

    `framework_ids` is the set of frameworks the philosophy's own package
    ships; when given, every phase must use one of them.
    """
    pid = phil.get('id', '?')
    errors: list[str] = []
    tracks = tracks_of(phil)
    if not tracks:
        return [f"{pid}: declares no tracks"]
    known_kinds = set(kinds())
    track_ids: set = set()
    for track in tracks:
        tid = track.get('id')
        if tid in track_ids:
            errors.append(f"{pid}: duplicate track id '{tid}'")
        track_ids.add(tid)
        phases = track.get('phases') or []
        if not phases:
            errors.append(f"{pid}/{tid}: track has no phases")
        phase_ids: set = set()
        for ph in phases:
            phid = ph.get('id')
            if phid in phase_ids:
                errors.append(f"{pid}/{tid}: duplicate phase id '{phid}'")
            phase_ids.add(phid)
            if ph.get('kind') not in known_kinds:
                errors.append(f"{pid}/{tid}/{phid}: unknown kind '{ph.get('kind')}'")
            for t in ph.get('tests') or []:
                week = t.get('week')
                if isinstance(week, int) and week > int(ph.get('weeks') or 1):
                    errors.append(f"{pid}/{tid}/{phid}: a test in week {week} of a {ph.get('weeks')}-week phase")
                if t.get('week') is not None and t.get('every') is not None:
                    errors.append(f"{pid}/{tid}/{phid}: a test gives both `week` and `every`")
                weeks = int(ph.get('weeks') or 1)
                first = t.get('start') or t.get('every')
                if not ph.get('repeatable') and isinstance(first, int) and first > weeks:
                    errors.append(f"{pid}/{tid}/{phid}: a test first due in week {first} "
                                  f"of a {weeks}-week phase never runs")
            fid = ph.get('framework_id')
            if not fid:
                errors.append(f"{pid}/{tid}/{phid}: no framework_id")
            elif framework_ids is not None and fid not in framework_ids:
                errors.append(f"{pid}/{tid}/{phid}: framework '{fid}' is not in this package")
    primary = phil.get('primary_track_id')
    if primary and primary not in track_ids:
        errors.append(f"{pid}: primary_track_id '{primary}' is not one of its tracks")
    for level, tid in (phil.get('track_for_level') or {}).items():
        if tid not in track_ids:
            errors.append(f"{pid}: track_for_level {level} names '{tid}', not one of its tracks")
    return errors


# ---------------------------------------------------------------------------
# Goal phase sequence
# ---------------------------------------------------------------------------

def phase_sequence_for(track: dict) -> list[dict]:
    """The goal's `phase_sequence` for a track.

    `phase` stays the kind, so every reader that predates tracks (archetype
    filters, analytics, the clients' colours) keeps working; `phase_id` is the
    philosophy's own id and the text keys come along for display.
    """
    out = []
    for ph in track.get('phases') or []:
        entry = {
            'phase_id': ph['id'],
            'phase': ph['kind'],
            'weeks': int(ph.get('weeks') or 1),
            'framework_id': ph.get('framework_id'),
        }
        for key in _PHASE_TEXT_KEYS:
            if ph.get(key) is not None:
                entry[key] = ph[key]
        if ph.get('priority_override'):
            entry['priority_override'] = dict(ph['priority_override'])
        if ph.get('exclude_exercises'):
            entry['exclude_exercises'] = list(ph['exclude_exercises'])
        if ph.get('rotate_main_lifts'):
            entry['rotate_main_lifts'] = True
        if ph.get('tests'):
            entry['tests'] = [dict(t) for t in ph['tests']]
        if ph.get('week_templates'):
            # The source's own week, day by day (Horsemen's month templates).
            entry['week_templates'] = [list(w) for w in ph['week_templates']]
            entry['drop_order'] = list(ph.get('drop_order') or [])
        if ph.get('checks'):
            entry['checks'] = dict(ph['checks'])
        if ph.get('former_ids'):
            entry['former_ids'] = list(ph['former_ids'])
        out.append(entry)
    return out


def resolve_start_phase(phase_seq: list, start_phase: str | None = None,
                        training_phase: str | None = None) -> str | None:
    """The `phase_id` generation starts at.

    `start_phase` is a phase id from this track; one the track does not
    contain is an error rather than a silent flat list on the default
    framework. `training_phase` is the legacy constraint (a kind — the iOS
    builder still sends base/build/peak/taper): it maps to the first phase of
    that kind, and to the first phase when the track has none of that kind,
    because the client offers the same four kinds for every philosophy.
    Neither given → the track's first phase, never a hard-coded 'base'.
    """
    if not phase_seq:
        return None
    if start_phase:
        for e in phase_seq:
            if e.get('phase_id') == start_phase:
                return start_phase
        # A phase a package renamed or merged (its `former_ids`) resolves to
        # the phase that replaced it: a stored week still names the old one.
        for e in phase_seq:
            if start_phase in (e.get('former_ids') or []):
                return e['phase_id']
        # A kind passed in the id field (older clients) still resolves.
        for e in phase_seq:
            if e.get('phase') == start_phase:
                return e['phase_id']
        raise PhaseResolutionError(
            f"Phase '{start_phase}' is not in this track: "
            f"{[e.get('phase_id') for e in phase_seq]}"
        )
    if training_phase:
        for e in phase_seq:
            if e.get('phase') == training_phase or e.get('phase_id') == training_phase:
                return e['phase_id']
    return phase_seq[0].get('phase_id')


def legacy_kind_missing(phase_seq: list, start_phase: str | None,
                        training_phase: str | None) -> bool:
    """True when a legacy kind was asked for that the track does not have."""
    if start_phase or not training_phase or not phase_seq:
        return False
    return not any(e.get('phase') == training_phase or e.get('phase_id') == training_phase
                   for e in phase_seq)


def phase_rules(philosophies: list, phase_id: str | None, framework_id: str | None = None) -> dict:
    """The generator-read keys of one phase, for routes that build a single
    session or swap one exercise rather than generate weeks.

    The phase is looked up by id among the given philosophies, narrowed by the
    framework it runs on when one is given (phase ids like 'base' recur across
    packages; a framework id does not). Nothing found is the empty rule set.
    """
    if not phase_id:
        return {'exclude_exercises': [], 'rotate_main_lifts': False}
    for phil in philosophies or []:
        for track in tracks_of(phil):
            for ph in track.get('phases') or []:
                if ph.get('id') != phase_id and phase_id not in (ph.get('former_ids') or []):
                    continue
                if framework_id and ph.get('framework_id') != framework_id:
                    continue
                return {'exclude_exercises': list(ph.get('exclude_exercises') or []),
                        'rotate_main_lifts': bool(ph.get('rotate_main_lifts'))}
    return {'exclude_exercises': [], 'rotate_main_lifts': False}


def week_entry(phase_entry: dict, week_in_phase: int, week_in_program: int) -> dict:
    """One generator week entry. The single constructor both the plain
    generate path and the event-date calendar use, so neither can drop the
    phase's framework again."""
    entry = {
        'phase': phase_entry.get('phase'),
        'week_in_phase': week_in_phase,
        'week_in_program': week_in_program,
    }
    if phase_entry.get('phase_id'):
        entry['phase_id'] = phase_entry['phase_id']
    if phase_entry.get('name'):
        entry['phase_name'] = phase_entry['name']
    if phase_entry.get('framework_id'):
        entry['framework_id'] = phase_entry['framework_id']
    if phase_entry.get('exclude_exercises'):
        entry['exclude_exercises'] = list(phase_entry['exclude_exercises'])
    if phase_entry.get('rotate_main_lifts'):
        entry['rotate_main_lifts'] = True
    if phase_entry.get('week_templates'):
        # The week of the phase's template this week runs (they repeat).
        templates = phase_entry['week_templates']
        entry['week_template'] = templates[(week_in_phase - 1) % len(templates)]
        entry['drop_order'] = list(phase_entry.get('drop_order') or [])
    if phase_entry.get('tests'):
        # What src/standard_tests.tests_for_week needs to place the phase's
        # tests by week in the phase (repeating every cycle when repeatable).
        entry['tests'] = phase_entry['tests']
        entry['phase_weeks'] = int(phase_entry.get('weeks') or 1)
        entry['repeatable'] = bool(phase_entry.get('repeatable'))
    return entry
