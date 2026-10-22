"""A session's workout icon: what is in it, where the modality says what kind.

One icon per session, for its main exercise, drawn the same on every client
and tinted with the session's modality colour (data/commons/workout_icons.json).
The first that names one wins:

  1. the lead archetype's `icon` — a contract day of several modules is led by
     its first, whose archetype and modality the session already carries;
  2. the lead exercise's `icon` — the first module's first exercise, else the
     first slot that is not preparation (analytics' PREPARATORY_ROLE_GLOBS);
  3. the archetype category's default (`category_defaults`).

None of them → no icon, and each client draws its modality icon as before.

Derived on read and never stored (`strip`), like `phase_summary`: a program
saved before an icon existed shows it, and an icon changed in the YAML reaches
every client without a regenerate.
"""
from __future__ import annotations

import fnmatch
import json
import os
from functools import lru_cache

from src import loader
from src.analytics.spec import PREPARATORY_ROLE_GLOBS

_VOCAB_PATH = os.path.join(os.path.dirname(__file__), '..', 'data', 'commons', 'workout_icons.json')

# Slot roles that prepare for or recover from the work rather than are it.
_PREPARATORY = PREPARATORY_ROLE_GLOBS + ('*recovery*',)


@lru_cache(maxsize=1)
def vocabulary() -> dict:
    with open(_VOCAB_PATH, encoding='utf-8') as f:
        return json.load(f)


def icon_ids() -> set[str]:
    return {i['id'] for i in vocabulary().get('icons', [])}


@lru_cache(maxsize=1)
def _archetypes() -> dict:
    return {a.get('id'): a for a in loader.load_all_archetypes()}


@lru_cache(maxsize=1)
def _exercise_icons() -> dict:
    """exercise id → icon; any package's copy that names one (sorted order)."""
    _, by_package = loader.load_all_exercises()
    out: dict = {}
    for pkg in sorted(by_package):
        for ex_id, ex in by_package[pkg].items():
            if ex.get('icon') and ex_id not in out:
                out[ex_id] = ex['icon']
    return out


def clear_cache() -> None:
    """For tests that swap the package directory."""
    vocabulary.cache_clear()
    _archetypes.cache_clear()
    _exercise_icons.cache_clear()


def _known(icon) -> str | None:
    return icon if isinstance(icon, str) and icon in icon_ids() else None


def for_archetype(archetype_id: str | None) -> str | None:
    """The icon an archetype id alone gives: its own, else its category's.

    What a history row (planned_sessions.archetype_id) or a watch's tomorrow
    line resolves with, where the session's exercises are not at hand.
    """
    arch = _archetypes().get(archetype_id) if archetype_id else None
    if not arch:
        return None
    return _known(arch.get('icon')) or _known(
        (vocabulary().get('category_defaults') or {}).get(arch.get('category')))


def _exercise_id(ea: dict) -> str | None:
    ex = ea.get('exercise')
    if isinstance(ex, dict):
        return ex.get('id')
    return ex if isinstance(ex, str) else ea.get('exercise_id')


def _lead_exercise(session: dict) -> str | None:
    modules = session.get('modules') or []
    if modules and (modules[0].get('exercise_ids') or []):
        return modules[0]['exercise_ids'][0]
    for ea in session.get('exercises') or []:
        if not isinstance(ea, dict) or any(ea.get(k) for k in (
                'injury_skip', 'injurySkip', 'coverage_gap', 'coverageGap')):
            continue
        role = str(ea.get('slot_role') or ea.get('slotRole')
                   or (ea.get('slot') or {}).get('role') or '')
        if any(fnmatch.fnmatch(role, pat) for pat in _PREPARATORY):
            continue
        ex_id = _exercise_id(ea)
        if ex_id:
            return ex_id
    return None


def _archetype_id(session: dict) -> str | None:
    arch = session.get('archetype')
    if isinstance(arch, dict) and arch.get('id'):
        return arch['id']
    modules = session.get('modules') or []
    return (modules[0].get('archetype_id') if modules else None) or session.get('archetype_id')


def session_icon(session: dict) -> str | None:
    if not isinstance(session, dict):
        return None
    arch_id = _archetype_id(session)
    arch = _archetypes().get(arch_id) or (session.get('archetype') if isinstance(session.get('archetype'), dict) else {}) or {}
    return (_known(arch.get('icon'))
            or _known(_exercise_icons().get(_lead_exercise(session)))
            or _known((vocabulary().get('category_defaults') or {}).get(arch.get('category'))))


def _sessions(weeks: list):
    for wk in weeks or []:
        sched = wk.get('schedule') if isinstance(wk, dict) else None
        if not isinstance(sched, dict):
            continue
        for sessions in sched.values():
            for s in sessions or []:
                if isinstance(s, dict):
                    yield s


def with_icons(weeks: list) -> list:
    """The weeks with each session's `icon` set (or removed when it has none)."""
    out = []
    for wk in weeks or []:
        sched = wk.get('schedule') if isinstance(wk, dict) else None
        if not isinstance(sched, dict):
            out.append(wk)
            continue
        new_sched = {}
        for day, sessions in sched.items():
            new_sessions = []
            for s in sessions or []:
                if not isinstance(s, dict):
                    new_sessions.append(s)
                    continue
                s = {k: v for k, v in s.items() if k != 'icon'}
                icon = session_icon(s)
                if icon:
                    s['icon'] = icon
                new_sessions.append(s)
            new_sched[day] = new_sessions
        out.append({**wk, 'schedule': new_sched})
    return out


def strip(current_program: dict) -> dict:
    """`current_program` without any session's `icon` (it is derived on read)."""
    weeks = current_program.get('weeks') if isinstance(current_program, dict) else None
    if not any('icon' in s for s in _sessions(weeks)):
        return current_program
    out = []
    for wk in weeks:
        sched = wk.get('schedule') if isinstance(wk, dict) else None
        if not isinstance(sched, dict):
            out.append(wk)
            continue
        out.append({**wk, 'schedule': {
            day: [{k: v for k, v in s.items() if k != 'icon'} if isinstance(s, dict) else s
                  for s in sessions or []]
            for day, sessions in sched.items()}})
    return {**current_program, 'weeks': out}
