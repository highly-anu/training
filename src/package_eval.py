"""The package scorecard: how far a package is from what its method prescribes.

The fidelity gate (src/fidelity.py) reads one program against what its
package declares. It cannot see that a declaration is thin: when the
scorecard was written most of its findings were intensity splits, while a novice Gym Jones program
was half substitutes, CrossFit ran one AMRAP template, and Starting Strength
with no barbell handed out sessions whose every slot was empty. The scorecard
grades each package × track on five dimensions — Source, Execution,
Robustness, Data, Measurement — each pass, partial or fail against named
criteria, never a blended number (docs/package-fidelity/README.md has the
table). `audited` in docs/package-fidelity/status.yaml is derived from it.

This module is pure: it grades programs and files already read. Generation,
the matrix of athlete profiles and the ratchet live in
tools/evaluate_packages.py; `test_package_eval.py` pins each grader.
"""
from __future__ import annotations

import re
from collections import Counter

from src import fidelity

PASS, PARTIAL, FAIL = 'pass', 'partial', 'fail'
RANK = {PASS: 0, PARTIAL: 1, FAIL: 2}

DIMENSIONS = {
    'source': ('S1', 'S2', 'S3', 'S4', 'S5'),
    'execution': ('E1', 'E2', 'E3', 'E4', 'E5', 'E6'),
    'robustness': ('R1',),
    'data': ('D1', 'D2', 'D3', 'D4'),
    'measurement': ('M1', 'M2', 'M3', 'M4'),
}
CRITERIA = {
    'S1': 'Dossier has Sources, Rules, Open, Inventions and Tests',
    'S2': 'Sources are primary, or a consensus of three or more',
    'S3': 'No rule left only in prose',
    'S4': "status.yaml's inventions match the dossier's",
    'S5': 'A source test that CI runs',
    'E1': 'No session with every slot empty',
    'E2': 'Sessions are their own modality, not substitutes',
    'E3': 'A level the track is not written for is refused',
    'E4': 'No archetype dominates its modality',
    'E5': "The phase's defining claims are declared and hold",
    'E6': 'No fidelity finding',
    'R1': 'Constraints keep the method, or refuse with what would unblock it',
    'D1': 'Every file valid against its schema',
    'D2': 'Every catalog exercise reaches a program',
    'D3': 'Exercise media',
    'D4': 'Movement patterns, archetype levels, no inert scaling',
    'M1': 'The lead measure is the method\'s own currency',
    'M2': 'The lead measure is captured by logging on both clients',
    'M3': 'Every declared standard has a test, a lift that estimates it, or a manual entry',
    'M4': 'Every referenced standard exists',
}
# Hygiene: reported, but never what keeps a package from `audited`.
HYGIENE = {'D3', 'D4'}

SUBSTITUTE_PARTIAL = 0.25
SHARE_PASS, SHARE_PARTIAL = 0.40, 0.60
LEVELS = ('novice', 'intermediate', 'advanced', 'elite')
DOSSIER_SECTIONS = ('Sources', 'Rules', 'Open', 'Inventions', 'Tests')
# Fidelity rules that are a declared claim of the method breaking, at any
# gated severity: the volume bands fire only where a phase declares them.
CLAIM_RULES = {'substituted_share', 'modality_outnumbers', 'archetype_share', 'distinct_archetypes',
               'archetype_required', 'modality_required', 'archetype_forbidden', 'zone_above_cap',
               'training_contract', 'contract_unfulfilled', 'template_foreign_day',
               'volume_ramp', 'volume_vs_previous_phase'}
CLAIM_KEYS = {'archetypes_required', 'archetypes_forbidden', 'modalities_required', 'max_zone',
              'volume_change_per_week', 'volume_vs_previous_phase', 'max_substituted_share',
              'modality_outnumbers', 'max_archetype_share', 'min_distinct_archetypes'}


def worst(grades) -> str:
    grades = list(grades)
    return max(grades, key=RANK.__getitem__) if grades else PASS


# ── Reading a program ─────────────────────────────────────────────────────────

def sessions(program: dict | None):
    """(week, session) for every session but a test's."""
    for w in (program or {}).get('weeks') or []:
        for _, s in fidelity._sessions(w):
            if not s.get('test'):
                yield w, s


def refused(program: dict | None, validation=None) -> bool:
    """The request was turned down rather than served."""
    if validation is not None and not validation.feasible:
        return True
    return not program or bool(program.get('validation_errors')) or not program.get('weeks')


def _where(w: dict, s: dict) -> str:
    return f"week {w.get('week_number')} {(s.get('archetype') or {}).get('id') or s.get('modality')}"


def empty_sessions(program: dict | None) -> list[str]:
    """Sessions with work slots, every one of them empty: delivered, nothing in it."""
    out = []
    for w, s in sessions(program):
        work = fidelity._work(s)
        if work and not any(ea.get('exercise') for ea in work):
            out.append(_where(w, s))
    return out


def gapped_sessions(program: dict | None) -> list[str]:
    """Sessions delivered with some work slots empty, but not all."""
    out = []
    for w, s in sessions(program):
        work = fidelity._work(s)
        filled = sum(1 for ea in work if ea.get('exercise'))
        if 0 < filled < len(work):
            out.append(_where(w, s))
    return out


def substitution(program: dict | None) -> tuple[int, int]:
    """(sessions another modality's for lack of their own, sessions)."""
    all_ = [s for _, s in sessions(program)]
    return sum(1 for s in all_ if s.get('substituted_for')), len(all_)


def claims_broken(program: dict | None, track: dict) -> list[str]:
    """The phase `checks:` claims the program breaks (src/fidelity.claim_violations)."""
    by_id = {p['id']: p for p in track.get('phases') or []}
    out = []
    for phase_id, pweeks in fidelity._phase_groups((program or {}).get('weeks') or []):
        checks = (by_id.get(phase_id) or {}).get('checks') or {}
        out += [f"{phase_id}: {detail}" for _, _, detail, _ in fidelity.claim_violations(pweeks, checks)]
    return out


def eligible_archetypes(archetypes: list, modality: str, kind: str, level: str, equipment: set) -> set:
    """Archetypes the scheduler could have picked for a modality's session."""
    out = set()
    for a in archetypes:
        if a.get('modality') != modality or a.get('pool_only') or 'test' in a:
            continue
        if a.get('applicable_phases') and kind not in a['applicable_phases']:
            continue
        if a.get('training_levels') and level not in a['training_levels']:
            continue
        if not set(a.get('required_equipment') or []) <= equipment | {'open_space', 'none'}:
            continue
        out.add(a['id'])
    return out


def concentration(program: dict | None, track: dict, archetypes: list, level: str,
                  equipment: set) -> list[tuple[str, str, str, float, float | None, int]]:
    """(phase, modality, archetype, share, declared cap, archetypes on offer) for
    the most used archetype of each modality with four or more sessions in a
    phase. A package that offers one template for a modality (CrossFit's AMRAP)
    concentrates as surely as a selector that keeps picking one; a method whose
    repetition is the point says so with the phase's `max_archetype_share`.
    Templated phases and contracts are exempt: their repetition is the source's."""
    by_id = {p['id']: p for p in track.get('phases') or []}
    out = []
    if (program or {}).get('training_contract'):
        return out
    for phase_id, pweeks in fidelity._phase_groups((program or {}).get('weeks') or []):
        phase = by_id.get(phase_id) or {}
        if phase.get('week_templates'):
            continue
        kind = pweeks[0].get('phase')
        for mod, aid, top, total in fidelity.archetype_shares(pweeks):
            out.append((phase_id, mod, aid, top / total, (phase.get('checks') or {}).get('max_archetype_share'),
                        len(eligible_archetypes(archetypes, mod, kind, level, equipment))))
    return out


def written_levels(track: dict, frameworks: dict, contract: dict | None) -> set:
    """The levels a track is written for: its contract's, else every phase
    framework's `applicable_when.training_level` (all four when none says)."""
    if contract:
        return set(contract.get('training_levels') or LEVELS)
    levels = set(LEVELS)
    for ph in track.get('phases') or []:
        declared = ((frameworks.get(ph.get('framework_id')) or {}).get('applicable_when') or {}).get('training_level')
        if declared:
            levels &= set(declared)
    return levels or set(LEVELS)


# ── Execution and robustness ─────────────────────────────────────────────────

def grade_e1(qualified: dict) -> tuple[str, str]:
    """`qualified`: profile -> program, for athletes the track is written for."""
    found = {p: empty_sessions(prog) for p, prog in qualified.items()}
    bad = {p: e for p, e in found.items() if e}
    if bad:
        p, e = next(iter(sorted(bad.items())))
        return FAIL, f"{p}: {len(e)} session(s) with every slot empty, e.g. {e[0]}"
    gapped = {p: g for p, prog in qualified.items() if (g := gapped_sessions(prog))}
    if gapped:
        p, g = next(iter(sorted(gapped.items())))
        return PARTIAL, f"{p}: {len(g)} session(s) with a slot empty, e.g. {g[0]}"
    return PASS, ''


def grade_e2(qualified: dict) -> tuple[str, str]:
    worst_share, where = 0.0, ''
    for p, prog in sorted(qualified.items()):
        n, total = substitution(prog)
        if total and n / total > worst_share:
            worst_share, where = n / total, f"{p}: {n} of {total} sessions substituted"
    if worst_share == 0:
        return PASS, ''
    return (PARTIAL if worst_share <= SUBSTITUTE_PARTIAL else FAIL), where


def grade_e3(other_levels: dict) -> tuple[str, str]:
    """`other_levels`: level -> was it refused, for levels the track is not written for."""
    served = sorted(lv for lv, was_refused in other_levels.items() if not was_refused)
    if not served:
        return PASS, ''
    return FAIL, f"served at {', '.join(served)}, which the track is not written for"


def grade_e4(found: list) -> tuple[str, str]:
    """A declared cap is the method's own word (pass within it); otherwise
    40 % passes and 60 % is partial."""
    graded = []
    for phase, mod, aid, share, cap, offered in found:
        detail = (f"{phase}: {aid} is {share:.0%} of {mod} "
                  f"({offered} archetype{'s' if offered != 1 else ''} on offer)")
        if cap is not None:
            graded.append((PASS if share <= cap + 1e-9 else FAIL, detail))
        else:
            graded.append((PASS if share <= SHARE_PASS else PARTIAL if share <= SHARE_PARTIAL else FAIL, detail))
    if not graded:
        return PASS, ''
    g = worst(x[0] for x in graded)
    return (PASS, '') if g == PASS else next(x for x in graded if x[0] == g)


def declares_claims(track: dict, contract: dict | None) -> bool:
    """A contract and a source week template are the method's claims made
    executable; otherwise a phase's `checks:` declares them."""
    if contract:
        return True
    return any(ph.get('week_templates') or (CLAIM_KEYS & set(ph.get('checks') or {}))
               for ph in track.get('phases') or [])


def grade_e5(declared: bool, broken: list[str]) -> tuple[str, str]:
    if broken:
        return FAIL, broken[0]
    if not declared:
        return PARTIAL, 'no defining claim declared (checks:, a contract or a week template)'
    return PASS, ''


def grade_e6(findings: list[dict]) -> tuple[str, str]:
    """`findings`: the track's gated fidelity findings (errors and warnings)."""
    if not findings:
        return PASS, ''
    errors = [f for f in findings if f['severity'] == 'error']
    rules = Counter(f['rule'] for f in findings)
    detail = ', '.join(f"{n} {r}" for r, n in rules.most_common())
    return (FAIL if errors else PARTIAL), detail


def robustness_outcome(program, validation, track: dict, unblocked: bool | None) -> tuple[str, str]:
    """One constrained profile: method kept, refused (with or without a way
    out), or degraded — served with empty sessions, mostly substitutes, or a
    defining claim broken."""
    if refused(program, validation):
        return (PASS, 'refused; one constraint lifted unblocks it') if unblocked else \
               (PARTIAL, 'refused, and no one constraint lifted unblocks it')
    empty = empty_sessions(program)
    n, total = substitution(program)
    broken = claims_broken(program, track)
    if empty:
        return FAIL, f"{len(empty)} session(s) with every slot empty"
    if total and n / total > SUBSTITUTE_PARTIAL:
        return FAIL, f"{n} of {total} sessions substituted"
    if broken:
        return FAIL, broken[0]
    return PASS, ''


def grade_r1(outcomes: dict) -> tuple[str, str]:
    """`outcomes`: profile -> robustness_outcome."""
    if not outcomes:
        return PASS, ''
    g = worst(o[0] for o in outcomes.values())
    if g == PASS:
        return PASS, ''
    bad = sorted((p, d) for p, (gr, d) in outcomes.items() if gr == g)
    return g, '; '.join(f"{p}: {d}" for p, d in bad[:3]) + (f" (+{len(bad) - 3})" if len(bad) > 3 else '')


# ── Data ─────────────────────────────────────────────────────────────────────

def grade_d1(errors: list[str]) -> tuple[str, str]:
    return (PASS, '') if not errors else (FAIL, errors[0])


def grade_d2(orphans: list[str]) -> tuple[str, str]:
    if not orphans:
        return PASS, ''
    return PARTIAL, f"{len(orphans)} orphaned: {', '.join(orphans[:4])}{'…' if len(orphans) > 4 else ''}"


def grade_d3(with_media: int, total: int) -> tuple[str, str]:
    share = with_media / total if total else 1.0
    detail = f"{with_media} of {total} exercises have media"
    if share >= 0.9:
        return PASS, ''
    return (PARTIAL if share >= 0.5 else FAIL), detail


def grade_d4(no_patterns: int, no_levels: int, inert_scaling: int) -> tuple[str, str]:
    parts = [f"{n} {what}" for n, what in ((no_patterns, 'exercises without movement patterns'),
                                          (no_levels, 'archetypes without training levels'),
                                          (inert_scaling, 'inert equipment_limited scalings')) if n]
    return (PASS, '') if not parts else (PARTIAL, '; '.join(parts))


# ── Measurement ──────────────────────────────────────────────────────────────

def grade_m1(declared: str | None, lead: str | None) -> tuple[str, str]:
    if not declared:
        return FAIL, f"no currency declared for the track (leads with {lead or 'nothing'})"
    if declared != lead:
        return FAIL, f"leads with {lead or 'nothing'}, the method's currency is {declared}"
    return PASS, ''


def grade_m2(primitive: str | None, primitives: dict, capture: dict) -> tuple[str, str]:
    if not primitive:
        return FAIL, 'no lead measure'
    kinds = {n: capture.get(n, 'device') for n in (primitives.get(primitive) or {}).get('needs') or []}
    weak = sorted(n for n, k in kinds.items() if k not in ('logged', 'program'))
    if not weak:
        return PASS, ''
    return PARTIAL, f"{primitive} needs {', '.join(f'{n} ({kinds[n]})' for n in weak)}"


def grade_m3(declared: list[str], tested: set, estimated: set, manual: set) -> tuple[str, str]:
    missing = [b for b in declared if b not in tested | estimated | manual]
    if not missing:
        return PASS, ''
    return PARTIAL, f"no test, estimating lift or manual entry: {', '.join(missing)}"


def grade_m4(referenced: set, known: set) -> tuple[str, str]:
    missing = sorted(referenced - known)
    return (PASS, '') if not missing else (FAIL, f"unknown standards: {', '.join(missing)}")


# ── Source ───────────────────────────────────────────────────────────────────

def dossier_sections(text: str) -> dict[str, list[str]]:
    """`## Heading` -> its bullet items (top-level `- ` lines)."""
    out: dict[str, list[str]] = {}
    current = None
    for line in text.splitlines():
        m = re.match(r'^##\s+(.*)', line)
        if m:
            current = m.group(1).strip()
            out[current] = []
        elif current is not None and line.startswith('- '):
            out[current].append(line[2:].strip())
    return out


def _section(sections: dict, name: str) -> list[str] | None:
    return next((v for k, v in sections.items() if k.split()[0].rstrip(':') == name), None)


def grade_s1(sections: dict | None) -> tuple[str, str]:
    if sections is None:
        return FAIL, 'no dossier'
    missing = [s for s in DOSSIER_SECTIONS if _section(sections, s) is None]
    return (PASS, '') if not missing else (FAIL, f"missing sections: {', '.join(missing)}")


def grade_s2(kind: str | None, sections: dict | None) -> tuple[str, str]:
    sources = len(_section(sections or {}, 'Sources') or [])
    if kind == 'primary' or (kind == 'consensus' and sources >= 3):
        return PASS, ''
    if kind in ('secondary', 'consensus'):
        return PARTIAL, f"{kind} sources ({sources})"
    return FAIL, 'sources_kind not stated'


def grade_s3(debt: list | None) -> tuple[str, str]:
    if debt is None:
        return PARTIAL, 'debt not stated'
    return (PASS, '') if not debt else (PARTIAL, f"{len(debt)} rule(s) only in prose")


def grade_s4(status_inventions: list, sections: dict | None) -> tuple[str, str]:
    if sections is None:
        return FAIL, 'no dossier'
    listed = _section(sections, 'Inventions') or []
    if len(listed) != len(status_inventions or []):
        return FAIL, f"dossier lists {len(listed)} invention(s), status.yaml {len(status_inventions or [])}"
    return PASS, ''


def grade_s5(tests_in_ci: int) -> tuple[str, str]:
    return (PASS, '') if tests_in_ci else (FAIL, 'no source test that CI runs')


# ── Status ───────────────────────────────────────────────────────────────────

def dimension_grades(grades: dict) -> dict:
    """{criterion: (grade, detail)} -> {dimension: grade}: its worst criterion
    that is not hygiene (hygiene is listed, never what a dimension reads)."""
    return {dim: worst(grades[c][0] for c in crits if c in grades and c not in HYGIENE)
            for dim, crits in DIMENSIONS.items()}


def derived_status(tracks: dict, excluded: set, has_dossier: bool) -> str:
    """`audited` when every criterion that is not hygiene passes on every
    track not excluded; `partial` once a dossier exists; else `not_started`."""
    counted = {t: g for t, g in tracks.items() if t not in excluded}
    if has_dossier and counted and all(g[c][0] == PASS for g in counted.values()
                                       for c in g if c not in HYGIENE):
        return 'audited'
    return 'partial' if has_dossier else 'not_started'
