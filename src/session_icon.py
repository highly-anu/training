"""A session's workout icon: what is in it, where the modality says what kind.

One icon per session, for its main exercise, drawn the same on every client
and tinted with the session's modality colour (data/commons/workout_icons.json).
The first that names one wins:

  1. the lead archetype's own `icon` — a contract day of several modules is led
     by its first, whose archetype and modality the session already carries;
  2. the lead exercise's own `icon`, else its category's default
     (`exercise_category_defaults`: a kettlebell exercise → `kettlebell`). The
     lead exercise is the first module's first, else the first slot that is
     not preparation (analytics' PREPARATORY_ROLE_GLOBS) or recovery;
  3. only when there is no exercise to read, the archetype category's default
     (`archetype_category_defaults`).

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
def _exercises() -> dict:
    """exercise id → (icon, category); the library's structural copy, with
    any package's `icon` for that id (sorted order)."""
    index, by_package = loader.load_all_exercises()
    icons: dict = {}
    for pkg in sorted(by_package):
        for ex_id, ex in by_package[pkg].items():
            if ex.get('icon') and ex_id not in icons:
                icons[ex_id] = ex['icon']
    return {ex_id: (icons.get(ex_id), ex.get('category')) for ex_id, ex in index.items()}


def clear_cache() -> None:
    """For tests that swap the package directory."""
    vocabulary.cache_clear()
    _archetypes.cache_clear()
    _exercises.cache_clear()


def _known(icon) -> str | None:
    return icon if isinstance(icon, str) and icon in icon_ids() else None


def _for_exercise(ex_id: str | None) -> str | None:
    icon, category = _exercises().get(ex_id, (None, None)) if ex_id else (None, None)
    return _known(icon) or _known((vocabulary().get('exercise_category_defaults') or {}).get(category))


def _for_archetype_category(arch: dict) -> str | None:
    return _known((vocabulary().get('archetype_category_defaults') or {}).get(arch.get('category')))


def _preparatory(role) -> bool:
    return any(fnmatch.fnmatch(str(role or ''), pat) for pat in _PREPARATORY)


def for_archetype(archetype_id: str | None) -> str | None:
    """The icon an archetype id alone gives: its own, else its lead slot's
    first named exercise's, else its category's.

    What a history row (planned_sessions.archetype_id) resolves with, where
    the session's exercises are not at hand.
    """
    arch = _archetypes().get(archetype_id) if archetype_id else None
    if not arch:
        return None
    if _known(arch.get('icon')):
        return arch['icon']
    for slot in arch.get('slots') or []:
        ids = (slot.get('exercise_filter') or {}).get('exercise_ids') or []
        if ids and not _preparatory(slot.get('role')):
            return _for_exercise(ids[0])
    return _for_archetype_category(arch)


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
        if _preparatory(ea.get('slot_role') or ea.get('slotRole') or (ea.get('slot') or {}).get('role')):
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
    own = session.get('archetype') if isinstance(session.get('archetype'), dict) else {}
    arch = _archetypes().get(_archetype_id(session)) or own or {}
    if _known(arch.get('icon')):
        return arch['icon']
    lead = _lead_exercise(session)
    if lead:
        return _for_exercise(lead)
    return _for_archetype_category(arch)


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
