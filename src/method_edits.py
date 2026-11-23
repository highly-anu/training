"""Text edits to an athlete's own method (a package they had built): its name
and summary, a track's and a phase's words, a session's name and notes, a
movement's note. Nothing else.

An edit here never changes a program — no id, no number, no slot, no
exercise — so it needs no model and no smoke generate: `apply` rewrites the
words in the package's own YAML and says what it could not do. Numbers and
structure stay with a revise build (docs/roadmap.md 21.10).

    edits = {name?, summary?,
             tracks:   {<track id>: {name?, description?,
                                     phases: {<phase id>: {name?, focus?, description?}}}},
             sessions: {<archetype id>: {name?, notes?, slots: {<role>: {notes?}}}}}

A name is 1–80 characters; other text at most 2000, and an empty one removes
the key. `apply` is pure: a file map in, a file map out.
"""
from __future__ import annotations

import yaml

NAME_MAX = 80
TEXT_MAX = 2000

# Edit key → the YAML key it writes, per level. A name is required where it
# stands; the others are optional text.
_PHILOSOPHY = {'name': 'name', 'summary': 'notes'}
_TRACK = {'name': 'name', 'description': 'description'}
_PHASE = {'name': 'name', 'focus': 'focus', 'description': 'description'}
_SESSION = {'name': 'name', 'notes': 'notes'}
_SLOT = {'notes': 'notes'}
_NAMES = ('name',)


def _problem(code: str, message: str, where: str | None = None) -> dict:
    return {'stage': 'edit', 'code': code, 'message': message, 'file': where}


def _text(value, key: str, where: str, problems: list) -> tuple[bool, str | None]:
    """(ok, text): the text as it will be written, None to remove the key."""
    if not isinstance(value, str):
        problems.append(_problem('not_text', f'{where}: {key} is text', where))
        return False, None
    text = ' '.join(value.split()) if key in _NAMES else value.strip()
    if any(ord(c) < 32 and c not in '\n\t' for c in text):
        problems.append(_problem('not_text', f'{where}: {key} holds a control character', where))
        return False, None
    if key in _NAMES:
        if not 1 <= len(text) <= NAME_MAX:
            problems.append(_problem('bad_name', f'{where}: a name is 1 to {NAME_MAX} characters', where))
            return False, None
        return True, text
    if len(text) > TEXT_MAX:
        problems.append(_problem('too_long', f'{where}: at most {TEXT_MAX} characters', where))
        return False, None
    return True, text or None


def _write(target: dict, edits: dict, allowed: dict, where: str, problems: list, nested: tuple = ()) -> bool:
    changed = False
    for key, value in edits.items():
        if key in nested:
            continue
        if key not in allowed:
            problems.append(_problem('not_editable', f"{where}: '{key}' cannot be edited here; "
                                     'numbers and structure change with a revise', where))
            continue
        ok, text = _text(value, key, where, problems)
        if not ok:
            continue
        yaml_key = allowed[key]
        if text is None:
            changed |= target.pop(yaml_key, None) is not None
        elif target.get(yaml_key) != text:
            target[yaml_key] = text
            changed = True
    return changed


def _dump(doc) -> str:
    return yaml.safe_dump(doc, sort_keys=False, allow_unicode=True, width=100, default_flow_style=False)


def _mapping(value, where: str, problems: list) -> dict:
    if isinstance(value, dict):
        return value
    problems.append(_problem('bad_edit', f'{where}: expected an object', where))
    return {}


def apply(files: dict, edits) -> tuple[dict, list[dict], list[str]]:
    """→ (the file map with the edits written, problems, the paths changed).
    With any problem nothing is to be saved."""
    problems: list[dict] = []
    if not isinstance(edits, dict) or not edits:
        return files, [_problem('bad_edit', 'nothing to edit')], []
    unknown = set(edits) - {'name', 'summary', 'tracks', 'sessions'}
    for key in sorted(unknown):
        problems.append(_problem('not_editable', f"'{key}' cannot be edited; numbers and structure change with a revise"))
    out = dict(files)
    changed: list[str] = []

    # philosophy.yaml: the method's own words, its tracks and their phases.
    if {'name', 'summary', 'tracks'} & set(edits):
        try:
            phil = yaml.safe_load(files.get('philosophy.yaml') or '')
        except yaml.YAMLError:
            phil = None
        if not isinstance(phil, dict):
            problems.append(_problem('unreadable', 'philosophy.yaml cannot be read', 'philosophy.yaml'))
        else:
            touched = _write(phil, {k: v for k, v in edits.items() if k in ('name', 'summary')},
                             _PHILOSOPHY, 'the method', problems)
            tracks = {t.get('id'): t for t in phil.get('tracks') or [] if isinstance(t, dict)}
            for track_id, track_edits in _mapping(edits.get('tracks', {}), 'tracks', problems).items():
                track = tracks.get(track_id)
                if track is None:
                    problems.append(_problem('unknown', f"the method has no track '{track_id}'", 'philosophy.yaml'))
                    continue
                track_edits = _mapping(track_edits, f'track {track_id}', problems)
                touched |= _write(track, track_edits, _TRACK, f'track {track_id}', problems, nested=('phases',))
                phases = {p.get('id'): p for p in track.get('phases') or [] if isinstance(p, dict)}
                for phase_id, phase_edits in _mapping(track_edits.get('phases', {}), f'track {track_id}', problems).items():
                    phase = phases.get(phase_id)
                    if phase is None:
                        problems.append(_problem('unknown', f"track '{track_id}' has no phase '{phase_id}'",
                                                 'philosophy.yaml'))
                        continue
                    touched |= _write(phase, _mapping(phase_edits, f'phase {phase_id}', problems), _PHASE,
                                      f'phase {phase_id}', problems)
            if touched:
                out['philosophy.yaml'] = _dump(phil)
                changed.append('philosophy.yaml')

    # A session is an archetype file; a movement's note is its slot's.
    sessions = _mapping(edits.get('sessions', {}), 'sessions', problems)
    if sessions:
        found: dict[str, tuple[str, dict]] = {}
        for path, content in files.items():
            if not path.startswith('archetypes/'):
                continue
            try:
                doc = yaml.safe_load(content)
            except yaml.YAMLError:
                continue
            if isinstance(doc, dict) and doc.get('id') in sessions:
                found[doc['id']] = (path, doc)
        for session_id, session_edits in sessions.items():
            if session_id not in found:
                problems.append(_problem('unknown', f"the method has no session '{session_id}'"))
                continue
            path, doc = found[session_id]
            session_edits = _mapping(session_edits, f'session {session_id}', problems)
            touched = _write(doc, session_edits, _SESSION, f'session {session_id}', problems, nested=('slots',))
            slots = {s.get('role'): s for s in doc.get('slots') or [] if isinstance(s, dict)}
            for role, slot_edits in _mapping(session_edits.get('slots', {}), f'session {session_id}', problems).items():
                slot = slots.get(role)
                if slot is None:
                    problems.append(_problem('unknown', f"session '{session_id}' has no slot '{role}'", path))
                    continue
                touched |= _write(slot, _mapping(slot_edits, f'slot {role}', problems), _SLOT,
                                  f'slot {role} of {session_id}', problems)
            if touched:
                out[path] = _dump(doc)
                changed.append(path)

    return (files, problems, []) if problems else (out, [], changed)


def rename_in_program(program: dict, package_id: str, files: dict) -> dict | None:
    """The stored program with the names it copied from this method brought
    up to date — the goal's, its track's and phases', each week's phase — or
    None when it copies none of them. Names only: nothing the skeleton or the
    content of a session reads."""
    current = program.get('currentProgram') if isinstance(program, dict) else None
    goal = current.get('goal') if isinstance(current, dict) else None
    if not isinstance(goal, dict):
        return None
    try:
        phil = yaml.safe_load(files.get('philosophy.yaml') or '')
    except yaml.YAMLError:
        return None
    if not isinstance(phil, dict):
        return None
    tracks = {t.get('id'): t for t in phil.get('tracks') or [] if isinstance(t, dict)}
    changed = False
    new_goal = dict(goal)
    track = goal.get('track') if isinstance(goal.get('track'), dict) else None
    mine = goal.get('id') == f'_phil_{package_id}' or (track or {}).get('philosophy_id') == package_id
    if not mine:
        return None
    if goal.get('id') == f'_phil_{package_id}' and phil.get('name') and goal.get('name') != phil['name']:
        new_goal['name'] = phil['name']
        changed = True
    source = tracks.get((track or {}).get('id'))
    phase_names = {}
    if track and source and track.get('philosophy_id') == package_id:
        phase_names = {p.get('id'): p.get('name') for p in source.get('phases') or [] if isinstance(p, dict)}
        if source.get('name') and track.get('name') != source['name']:
            new_goal['track'] = {**track, 'name': source['name']}
            changed = True
        sequence = []
        for entry in goal.get('phase_sequence') or []:
            name = phase_names.get(entry.get('id')) if isinstance(entry, dict) else None
            if name and entry.get('name') != name:
                entry = {**entry, 'name': name}
                changed = True
            sequence.append(entry)
        if goal.get('phase_sequence'):
            new_goal['phase_sequence'] = sequence
    weeks = []
    for week in current.get('weeks') or []:
        name = phase_names.get(week.get('phase_id')) if isinstance(week, dict) else None
        if name and week.get('track_id') == (track or {}).get('id') and week.get('phase_name') != name:
            week = {**week, 'phase_name': name}
            changed = True
        weeks.append(week)
    if not changed:
        return None
    return {**program, 'currentProgram': {**current, 'goal': new_goal, 'weeks': weeks}}
