"""What the watch shows for a session: the resolved screen spec.

A package may declare its watch screens (`data/packages/<id>/watch.yaml`,
schema in docs/schemas/watch.schema.json) from the vocabulary in
`data/commons/watch_vocabulary.json`. When it does not, every slot gets the
vocabulary's default for its slot type, which is what the watch drew before
packages owned their screens. Nothing here names a philosophy: a new package
with a watch.yaml gets its own screens with no change to this file or to the
watch's core.

Resolution, most specific last (each layer deep-merges over the one before):

    package  defaults.slot_types.<type>
    archetype (keys at its top level apply to all of its slots)
    archetype slot_types.<type>
    archetype slots.<role>
    archetype slots.<role>.slot_types.<type>

over the default of the template that wins: the slot type's, unless a layer
names another `template`, in which case that template's defaults are the base
(a class's time_domain slots that become `round_timer` take the round timer's
fields, not the timed block's).

`session_screens` deduplicates the resolved specs of one session into a table
the watch reads by key, so a session of eight sets_reps slots carries one spec.
"""
from __future__ import annotations

import copy
import json
import os
from functools import lru_cache

from src import loader

_VOCAB_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    'data', 'commons', 'watch_vocabulary.json',
)

SPEC_KEYS = ('template', 'title', 'a', 'b', 'gauge', 'lines', 'lap',
             'behaviours', 'phases', 'module_screen')


@lru_cache(maxsize=1)
def vocabulary() -> dict:
    with open(_VOCAB_PATH) as f:
        return json.load(f)


def spec_version() -> int:
    return int(vocabulary()['version'])


@lru_cache(maxsize=1)
def _declared() -> dict:
    return loader.load_watch_specs()


def clear_cache() -> None:
    """Forget loaded specs (tests that add a throwaway package call this)."""
    _declared.cache_clear()
    vocabulary.cache_clear()
    _owners.cache_clear()
    _philosophy_name.cache_clear()


def _merge(base: dict, over: dict) -> dict:
    out = copy.deepcopy(base)
    for k, v in (over or {}).items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = _merge(out[k], v)
        else:
            out[k] = copy.deepcopy(v)
    return out


def _spec_part(d: dict) -> dict:
    return {k: v for k, v in (d or {}).items() if k in SPEC_KEYS}


def template_for_slot_type(slot_type: str | None) -> str:
    d = vocabulary()['defaults']
    return d['slot_types'].get(slot_type or '', d['fallback_template'])


def template_defaults(template: str) -> dict:
    t = vocabulary()['templates'].get(template) or {}
    return dict(t.get('defaults') or {}, template=template)


def package_spec(package_id: str | None) -> dict:
    """The package's declared watch spec, or {} when it ships none."""
    if not package_id:
        return {}
    return _declared().get(package_id) or {}


def resolve(package_id: str | None, archetype_id: str | None,
            slot_role: str | None, slot_type: str | None) -> dict:
    """The screen spec for one slot of one archetype, fully resolved."""
    pkg = package_spec(package_id)
    layers = [((pkg.get('defaults') or {}).get('slot_types') or {}).get(slot_type or '')]
    arch = (pkg.get('archetypes') or {}).get(archetype_id or '') or {}
    if arch:
        slot = (arch.get('slots') or {}).get(slot_role or '') or {}
        layers += [
            _spec_part(arch),
            (arch.get('slot_types') or {}).get(slot_type or ''),
            slot,
            (slot.get('slot_types') or {}).get(slot_type or ''),
        ]
    over: dict = {}
    for layer in layers:
        if layer:
            over = _merge(over, _spec_part(layer))

    template = over.get('template') or template_for_slot_type(slot_type)
    spec = _merge(template_defaults(template), over)
    spec['template'] = template
    spec.setdefault('gauge', spec.get('a'))
    if not spec.get('behaviours'):
        spec.pop('behaviours', None)
    return spec


def session_identity(package_id: str | None) -> dict:
    """Package-level watch settings: identity, summary pages, edit steps, module."""
    v = vocabulary()['defaults']
    pkg = package_spec(package_id)
    label = (pkg.get('identity') or {}).get('label')
    if not label and package_id:
        label = _philosophy_name(package_id)
    out = {
        'label': label,
        'accent': (pkg.get('identity') or {}).get('accent', v['identity']['accent']),
        'summary': _merge(v['summary'], pkg.get('summary') or {}),
        'edit': _merge(v['edit'], pkg.get('edit') or {}),
    }
    if pkg.get('module'):
        out['module'] = pkg['module']
    return out


@lru_cache(maxsize=None)
def _philosophy_name(package_id: str) -> str | None:
    try:
        return (loader.load_philosophy(package_id) or {}).get('name')
    except Exception:
        return None


@lru_cache(maxsize=1)
def _owners() -> dict:
    return {a.get('id'): a.get('_package') for a in loader.load_all_archetypes()}


def session_package(session: dict) -> str | None:
    """The package whose screens a stored session uses: the archetype's owner.

    A borrowed session (an Uphill program running a Horsemen ruck) shows its
    owner's screens, as it is built from its owner's archetype; the session's
    provenance tag is the fallback for an archetype no longer in the library.
    """
    arch_id = (session.get('archetype') or {}).get('id')
    owner = _owners().get(arch_id) if arch_id else None
    return owner or (session.get('provenance') or {}).get('package')


def session_screens(package_id: str | None, archetype_id: str | None,
                    slots: list[tuple[str | None, str | None]]) -> tuple[dict, list[str]]:
    """Resolve each (slot_role, slot_type) and deduplicate into a keyed table.

    Returns ({key: spec}, [key per slot]). Keys are 's0', 's1', … in order of
    first use, so the payload is deterministic.
    """
    table: dict = {}
    by_canon: dict = {}
    keys: list[str] = []
    for role, slot_type in slots:
        spec = resolve(package_id, archetype_id, role, slot_type)
        canon = json.dumps(spec, sort_keys=True)
        key = by_canon.get(canon)
        if key is None:
            key = f's{len(table)}'
            by_canon[canon] = key
            table[key] = spec
        keys.append(key)
    return table, keys


# ── validation (tools/check_provenance.py and test_watch_spec.py) ─────────────

def spec_errors(spec: dict, where: str) -> list[str]:
    """Vocabulary errors in one (partial or resolved) screen spec."""
    v = vocabulary()
    errs: list[str] = []
    tpl = spec.get('template')
    if tpl is not None and tpl not in v['templates']:
        errs.append(f'{where}: unknown template {tpl!r}')
    for key in ('a', 'b', 'gauge'):
        f = spec.get(key)
        if f is not None and f not in v['fields']:
            errs.append(f'{where}: unknown field {key}={f!r}')
    for part in spec.get('title') or []:
        if part not in v['title_parts']:
            errs.append(f'{where}: unknown title part {part!r}')
    if len(spec.get('title') or []) > v['limits']['title_parts']:
        errs.append(f"{where}: more than {v['limits']['title_parts']} title parts")
    if spec.get('lines') is not None and spec['lines'] not in v['lines']:
        errs.append(f"{where}: unknown lines {spec['lines']!r}")
    if spec.get('lap') is not None and spec['lap'] not in v['actions']:
        errs.append(f"{where}: unknown lap action {spec['lap']!r}")
    for b in (spec.get('behaviours') or {}):
        if b not in v['behaviours']:
            errs.append(f'{where}: unknown behaviour {b!r}')
    if len(spec.get('phases') or []) > v['limits']['phases']:
        errs.append(f"{where}: more than {v['limits']['phases']} phases")
    return errs


# The LAP actions that move a side-tracked step to the other side.
_SIDE_LAPS = {'complete_set', 'toggle_hold', 'next_side'}


def resolved_errors(spec: dict, where: str) -> list[str]:
    """Errors only a resolved spec can have: a LAP its template does not
    allow, a field whose behaviour is missing, a phases line with no phases."""
    v = vocabulary()
    errs = spec_errors(spec, where)
    tpl = v['templates'].get(spec.get('template')) or {}
    if spec.get('lap') and spec['lap'] not in (tpl.get('actions') or []):
        errs.append(f"{where}: lap {spec['lap']!r} is not allowed on template {spec.get('template')!r}")
    behaviours = spec.get('behaviours') or {}
    for key in ('a', 'b', 'gauge'):
        need = (v['fields'].get(spec.get(key)) or {}).get('requires')
        if need and need not in behaviours:
            errs.append(f'{where}: field {spec[key]!r} needs the {need!r} behaviour')
    if spec.get('lines') == 'ladder_total' and 'ladder' not in behaviours:
        errs.append(f"{where}: lines 'ladder_total' needs the 'ladder' behaviour")
    if behaviours.get('side_tracked') and spec.get('lap') not in _SIDE_LAPS:
        errs.append(f"{where}: side_tracked never alternates with lap {spec.get('lap')!r}"
                    f" (use one of {sorted(_SIDE_LAPS)})")
    if behaviours.get('side_tracked') and 'side' not in (spec.get('title') or []):
        errs.append(f"{where}: side_tracked shows no side without the 'side' title part")
    if spec.get('lines') == 'phases' and not spec.get('phases'):
        errs.append(f"{where}: lines 'phases' needs a phases list")
    return errs
