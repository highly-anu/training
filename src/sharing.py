"""What a shared link carries, and what its receiver can do with it
(docs/roadmap.md item 25; the rows are src/share_store.py's).

Three kinds:

  package  an athlete's own method: its files, the files of the sharer's own
           packages it borrows from, and the Explore document built in the
           sharer's view — a receiver cannot load the sharer's package, so the
           link carries what its page shows. A shipped package is only its id.
  program  a recipe — which methods, tracks and weights, the start phase, the
           length, a contract's options — never the weeks: the sharer's loads,
           schedule and earned progress are theirs. The receiver generates it
           on their own profile. With it, the packages it needs.
  session  one planned session as it stood, with its blocks and icon.

Every id an athlete's package declares carries its owner's prefix
(package_store.owner_prefix) and the gate refuses another's, so a package is
saved by `rehome`: the sharer's prefix becomes the receiver's in every file's
text and path. The builders are called in the sharer's view (the loader's
overlay names their packages); `availability` and `save` in the receiver's.
"""
from __future__ import annotations

import re

from src import loader, package_store

_PRIVATE = re.compile(r'^u[0-9a-f]{8}_')


def private_prefix(package_id) -> str | None:
    """The owner prefix of an athlete's own package id; None for a shipped one."""
    m = _PRIVATE.match(str(package_id or ''))
    return m.group(0) if m else None


def _swap(text: str, from_prefix: str, to_prefix: str) -> str:
    return re.sub(r'(?<![A-Za-z0-9_])' + re.escape(from_prefix), to_prefix, text)


def rehome(files: dict, from_prefix: str, to_prefix: str) -> dict:
    """A package's files as another athlete's: every id that starts with the
    one prefix starts with the other, in each file's text and in its path (a
    framework's file is named for its id)."""
    if from_prefix == to_prefix:
        return dict(files)
    return {_swap(path, from_prefix, to_prefix): _swap(text, from_prefix, to_prefix) for path, text in files.items()}


def rehome_id(identifier, from_prefix: str | None, to_prefix: str):
    if not from_prefix or not isinstance(identifier, str):
        return identifier
    return _swap(identifier, from_prefix, to_prefix)


# ── What a link carries ───────────────────────────────────────────────────────

def _borrowed(package_id: str) -> list[str]:
    from src.provenance import _parse_borrows
    try:
        return list(_parse_borrows(loader.load_philosophy(package_id)))
    except (FileNotFoundError, KeyError):
        return []


def _name(package_id: str) -> str:
    try:
        return loader.load_philosophy(package_id).get('name') or package_id
    except (FileNotFoundError, KeyError):
        return package_id


def needs(package_ids) -> list[str]:
    """The packages a program built from these needs: themselves and what
    they borrow from, each before the package that borrows it."""
    out: list[str] = []

    def add(pid, trail=()):
        if pid in out or pid in trail:
            return
        for b in _borrowed(pid):
            add(b, trail + (pid,))
        out.append(pid)
    for pid in package_ids:
        add(pid)
    return out


def snapshots(user_id: str, package_ids) -> list[dict]:
    """The sharer's own packages among `needs(package_ids)`, in install order:
    [{id, name, revision, files}]. A shipped package needs no snapshot."""
    out = []
    for pid in needs(package_ids):
        if not private_prefix(pid):
            continue
        row = package_store.get_package(user_id, pid)
        if row:
            out.append({'id': pid, 'name': row.get('name') or pid, 'revision': row['revision'], 'files': row['files']})
    return out


def _methods(package_ids) -> list[dict]:
    return [{'id': pid, 'name': _name(pid), 'private': bool(private_prefix(pid))} for pid in needs(package_ids)]


def package_payload(user_id: str, package_id: str) -> dict | None:
    """A method's link; None for a package the sharer does not see."""
    from src import explore_philosophy
    describe = explore_philosophy.describe(package_id)
    if describe is None:
        return None
    return {'id': package_id, 'name': describe.get('name') or _name(package_id),
            'prefix': package_store.owner_prefix(user_id), 'engineRev': package_store.engine_rev(),
            'methods': _methods([package_id]), 'packages': snapshots(user_id, [package_id]), 'describe': describe}


def program_recipe(envelope: dict) -> dict | None:
    """The request that builds this program again for anyone: generate's body
    without constraints, dates or state. None when the program names no
    philosophy (the server's reading of lib/programSource.regenerateSource,
    from the program's first week)."""
    program = (envelope or {}).get('currentProgram') or {}
    weeks = program.get('weeks') or []
    goal = program.get('goal') or {}
    first = weeks[0] if weeks else {}
    recipe: dict = {'num_weeks': len(weeks)} if weeks else {}
    lanes = (program.get('composition') or {}).get('lanes') or []
    if len(lanes) > 1:
        at = {l.get('lane_key'): l for l in first.get('lanes') or []}
        recipe['lanes'] = [{'philosophy_id': l.get('philosophy_id'), 'track_id': l.get('track_id'),
                            'weight': l.get('weight'),
                            **({'start_phase': at[l.get('key')]['phase_id']}
                               if (at.get(l.get('key')) or {}).get('phase_id') else {})} for l in lanes]
    else:
        ids = [i for i in envelope.get('sourceGoalIds') or [] if i and i != '_blended']
        if not ids:
            ids = [i for i in goal.get('primary_sources') or [] if i]
        if not ids and str(goal.get('id') or '').startswith('_phil_') and goal.get('id') != '_phil_blend':
            ids = [goal['id'][len('_phil_'):]]
        if not ids:
            return None
        if len(ids) == 1:
            recipe['philosophy_id'] = ids[0]
        else:
            weights = envelope.get('sourceGoalWeights') or {}
            recipe['philosophy_ids'] = ids
            recipe['philosophy_weights'] = {i: weights.get(i, 1) for i in ids}
        track = first.get('track_id') or (goal.get('track') or {}).get('id')
        if track:
            recipe['track_id'] = track
        if first.get('phase_id'):
            recipe['start_phase'] = first['phase_id']
    options = (program.get('constraints') or {}).get('contract_options')
    if options:
        recipe['contract_options'] = options
    return recipe


def recipe_packages(recipe: dict) -> list[str]:
    if recipe.get('lanes'):
        ids = [l.get('philosophy_id') for l in recipe['lanes']]
    else:
        ids = [recipe.get('philosophy_id')] if recipe.get('philosophy_id') else list(recipe.get('philosophy_ids') or [])
    return list(dict.fromkeys(i for i in ids if i))


def _program_summary(envelope: dict) -> dict:
    program = envelope.get('currentProgram') or {}
    goal, weeks = program.get('goal') or {}, program.get('weeks') or []
    phases: list[dict] = []
    for w in weeks:
        key = w.get('phase_id') or w.get('phase')
        if phases and phases[-1]['id'] == key:
            phases[-1]['weeks'] += 1
        else:
            phases.append({'id': key, 'name': w.get('phase_name') or key, 'kind': w.get('phase'), 'weeks': 1})
    sessions = [sum(len(ss or []) for ss in (w.get('schedule') or {}).values()) for w in weeks]
    days = [sum(1 for ss in (w.get('schedule') or {}).values() if ss) for w in weeks]
    lanes = (program.get('composition') or {}).get('lanes') or []
    tracks = ([{'name': l.get('name'), 'weight': l.get('weight')} for l in lanes] if len(lanes) > 1
              else [{'name': (goal.get('track') or {}).get('name')}] if (goal.get('track') or {}).get('name') else [])
    return {'name': goal.get('name'), 'weeks': len(weeks), 'phases': phases, 'tracks': tracks,
            'daysPerWeek': max(days) if days else None, 'sessionsPerWeek': max(sessions) if sessions else None}


def program_payload(user_id: str, envelope: dict) -> dict | None:
    """A program's link; None when it has no recipe."""
    recipe = program_recipe(envelope)
    if not recipe:
        return None
    ids = recipe_packages(recipe)
    summary = _program_summary(envelope)
    return {'name': summary.get('name') or 'Program', 'prefix': package_store.owner_prefix(user_id),
            'engineRev': package_store.engine_rev(), 'recipe': recipe, 'summary': summary,
            'methods': _methods(ids), 'packages': snapshots(user_id, ids)}


def session_payload(session: dict, week: dict, day: str, *, package: str | None = None,
                    modality_display: dict | None = None) -> dict:
    """One planned session as its page shows it: the session with its icon
    and blocks, where it stood in the program, its method's name."""
    from src import session_blocks, session_icon
    shown = dict(session)
    shown['icon'] = session_icon.session_icon(session)
    shown['blocks'] = session_blocks.for_session(session)
    name = (session.get('archetype') or {}).get('name') or session.get('category_name') or 'Session'
    out = {'name': name, 'session': shown, 'day': day,
           'week': {k: week.get(k) for k in ('week_number', 'week_in_phase', 'phase', 'phase_name', 'is_deload')}}
    if package:
        out['method'] = {'id': package, 'name': _name(package)}
    if modality_display:
        out['modalityDisplay'] = modality_display
    return out


# ── The page ──────────────────────────────────────────────────────────────────

def document(share: dict) -> dict:
    """What the link's page shows to anyone: never a package's files."""
    payload = share['payload']
    doc = {'token': share['token'], 'kind': share['kind'], 'title': share.get('title'),
           'createdAt': share.get('createdAt')}
    if share['kind'] == 'session':
        doc['session'] = payload
    elif share['kind'] == 'package':
        doc['method'] = {'id': payload['id'], 'name': payload['name'], 'describe': payload.get('describe'),
                         'shipped': not payload.get('packages')}
        doc['methods'] = payload.get('methods') or []
    else:
        doc['program'] = payload['summary']
        doc['methods'] = payload.get('methods') or []
    return doc


# ── The receiver ──────────────────────────────────────────────────────────────

def _states(payload: dict, user_id: str) -> list[dict]:
    """Each package the link needs, as the receiver holds it: `shipped`,
    `have` (their copy is this one), `different` (their copy of that id is
    another) or `missing`. `id` is the id it has, or would have, for them."""
    mine = package_store.owner_prefix(user_id)
    theirs = payload.get('prefix') or ''
    snaps = {p['id']: p for p in payload.get('packages') or []}
    shipped = {p['id'] for p in _shipped_philosophies()}
    out = []
    for m in payload.get('methods') or []:
        snap = snaps.get(m['id'])
        if not snap:
            out.append({'id': m['id'], 'name': m['name'], 'state': 'shipped' if m['id'] in shipped else 'missing',
                        'savable': False})
            continue
        new_id = rehome_id(m['id'], theirs, mine)
        held = package_store.get_package(user_id, new_id)
        if held is None:
            state = 'missing'
        elif package_store.files_digest(held['files']) == package_store.files_digest(rehome(snap['files'], theirs, mine)):
            state = 'have'
        else:
            state = 'different'
        out.append({'id': new_id, 'name': m['name'], 'state': state, 'savable': True, 'source': m['id']})
    return out


def _shipped_philosophies() -> list:
    with loader.overlay(None):
        return loader.load_philosophies()


def availability(share: dict, user_id: str) -> dict:
    """What the signed-in viewer has of what the link needs. `ready`: nothing
    is missing; `toSave`: how many packages a save would add."""
    payload = share['payload']
    yours = share.get('userId') == user_id
    states = _states(payload, user_id) if share['kind'] != 'session' else []
    for s in states:
        s.pop('source', None)
    missing = [s for s in states if s['state'] in ('missing', 'different')]
    held = len(package_store.list_packages(user_id))
    return {'yours': yours, 'methods': states,
            'ready': not any(s['state'] == 'missing' for s in states),
            'toSave': sum(1 for s in missing if s['savable']),
            'room': max(0, package_store.MAX_PACKAGES - held)}


def recipe_for(share: dict, user_id: str) -> dict | None:
    """The program link's recipe with the receiver's ids: a package's id, and
    the track and phase ids that carry its prefix."""
    import json
    payload = share['payload']
    recipe = payload.get('recipe')
    if not recipe:
        return None
    theirs, mine = payload.get('prefix') or '', package_store.owner_prefix(user_id)
    if not payload.get('packages') or not theirs or theirs == mine:
        return dict(recipe)
    return json.loads(re.sub(r'(?<![A-Za-z0-9_])' + re.escape(theirs), mine, json.dumps(recipe)))


class Different(Exception):
    """The receiver holds another package under an id the link would save."""

    def __init__(self, methods):
        super().__init__('different')
        self.methods = methods


def save(share: dict, user_id: str, *, replace: bool = False) -> dict:
    """Save the link's packages the receiver lacks, borrowed ones first, each
    through every gate as their own (package_store.install). → {ok, installed:
    [{id, name}], problems?}; the first package the gates refuse stops it.
    Raises Different when a copy of theirs would be overwritten and `replace`
    is not set; package_store.StoreError when a write fails."""
    payload = share['payload']
    theirs, mine = payload.get('prefix') or '', package_store.owner_prefix(user_id)
    states = [s for s in _states(payload, user_id) if s['savable']]
    clash = [s for s in states if s['state'] == 'different']
    if clash and not replace:
        raise Different([{'id': s['id'], 'name': s['name']} for s in clash])
    snaps = {p['id']: p for p in payload.get('packages') or []}
    installed = []
    for s in states:
        if s['state'] == 'have':
            continue
        result = package_store.install(user_id, rehome(snaps[s['source']]['files'], theirs, mine))
        if not result.get('installed'):
            return {'ok': False, 'installed': installed, 'package': s['id'], 'name': s['name'],
                    'problems': result.get('problems') or [],
                    'olderEngine': payload.get('engineRev') != package_store.engine_rev()}
        installed.append({'id': s['id'], 'name': s['name'], 'revision': result.get('revision')})
    return {'ok': True, 'installed': installed}
