"""Explore ▸ Philosophies: one philosophy as its package writes it.

The page used to be assembled in the browser from the raw lists, with its own
copies of the engine's rules, and read the wrong sources: every shipped phase
runs a training contract or a week template, while the page showed the
framework's `sessions_per_week`; the slot matcher never read `exercise_ids`,
which 1,748 of 1,769 slots use; and the browser added every framework's
sessions into a profile, a one-week taper counting as much as a sixteen-week
base. Here the server reads the package once and says it in words — the
analytics specs' pattern (`src/analytics/describe.py`) — and the clients lay it
out.

What a phase's week holds comes from what builds it: a training contract's
modules running in that phase, a phase's `week_templates` (the source's own
days) or, for a phase with neither, its framework's sessions per week. The
rules, inventions and open questions come from the package's fidelity record
(`fidelity.yaml`); a package without one has none to show.

Pure over the loaded data: `build(...)` takes the lists, `describe(id)` reads
them once per process.
"""
from __future__ import annotations

import os

from src import goals, loader, phases, training_contract
from src.analytics import benchmarks_data
from src.explore_links import policy_for, slot_exercises

WEEKDAYS = ('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday')

_PROGRESSION_WORDS = {
    'density_cycle': 'more reps in the same minutes, then more rounds, then a heavier bell',
    'timed_cycle': 'longer work periods, up to a ceiling',
    'weekly_volume': 'weekly minutes that build, then recover',
    'load_per_exposure': 'weight on the bar each session it is made',
    'skill_hold': 'the same practice repeated until it is clean',
}


def words(identifier: str | None) -> str:
    """`polarized_80_20_uphill` → "Polarized 80 20 uphill". The one copy, until
    the packages write these words themselves (roadmap item 17, slice 4)."""
    text = (identifier or '').replace('_', ' ').strip()
    return text[:1].upper() + text[1:]


def _listify(value) -> list:
    if value is None:
        return []
    return [value] if isinstance(value, str) else list(value)


def _num(n) -> str:
    return f'{n:g}' if isinstance(n, (int, float)) else str(n)


def _duration(seconds) -> str:
    seconds = int(seconds)
    if seconds >= 3600 and seconds % 60 == 0:
        h, m = divmod(seconds // 60, 60)
        return f'{h} h' + (f' {m} min' if m else '')
    if seconds >= 60:
        m, s = divmod(seconds, 60)
        return f'{m} min' + (f' {s} s' if s else '')
    return f'{seconds} s'


def prescription(item: dict) -> str:
    """A slot's or a contract block's prescription in one line: "3 × 5 · 5 min
    rest", "21-15-9", "20 min · zone 2". The notes say the rest."""
    parts: list[str] = []
    scheme = item.get('rep_scheme')
    rounds = item.get('rounds')
    sets, reps = item.get('sets'), item.get('reps')
    if scheme:
        parts.append('-'.join(_num(r) for r in scheme))
    elif rounds and item.get('reps_per_round'):
        parts.append(f"{_num(rounds)} rounds × {_num(item['reps_per_round'])}")
    elif rounds and rounds != 1:
        parts.append(f'{_num(rounds)} rounds')
    elif item.get('reps_per_round'):
        parts.append(f"{_num(item['reps_per_round'])} a round")
    if sets and reps is not None:
        parts.append(f'{_num(sets)} × {"max" if reps == "max" else _num(reps)}')
    elif sets and item.get('hold_seconds'):
        parts.append(f"{_num(sets)} × {_num(item['hold_seconds'])} s hold")
    elif sets and (item.get('hold_sec')):
        parts.append(f"{_num(sets)} × {_num(item['hold_sec'])} s hold")
    elif sets:
        parts.append(f'{_num(sets)} sets')
    elif reps is not None:
        parts.append(f'{_num(reps)} reps')
    elif item.get('hold_seconds'):
        parts.append(f"{_num(item['hold_seconds'])} s hold")
    if item.get('work_sec'):
        parts.append(f"{_num(item['work_sec'])} s on")
    if item.get('duration_minutes'):
        parts.append(f"{_num(item['duration_minutes'])} min")
    elif item.get('duration_sec') and item.get('slot_type') in ('time_domain', 'amrap', 'amrap_movement', 'emom'):
        parts.append(_duration(item['duration_sec']))
    if item.get('distance_m'):
        d = item['distance_m']
        parts.append(f'{d / 1000:g} km' if d >= 1000 else f'{_num(d)} m')
    if item.get('slot_type') == 'for_time':
        parts.append('for time')
    elif item.get('slot_type') in ('amrap', 'amrap_movement') and not item.get('duration_minutes'):
        parts.append('as many as possible')
    if item.get('load'):
        parts.append(str(item['load']))
    if item.get('intensity'):
        parts.append(words(item['intensity']).lower())
    if item.get('rpe_target'):
        parts.append(f"RPE {_num(item['rpe_target'])}")
    if item.get('rest_sec'):
        parts.append(f"{_duration(item['rest_sec'])} rest")
    return ' · '.join(parts)


# ─── Weeks ───────────────────────────────────────────────────────────────────

def _template_week(phase: dict, framework: dict) -> dict:
    """The source's own days: one list of seven per template week, each day its
    categories by name and modality."""
    categories = framework.get('categories') or {}
    warm = framework.get('warm_up_category')

    def piece(cat: str) -> dict:
        c = categories.get(cat) or {}
        return {'category': cat, 'name': c.get('name') or words(cat), 'modality': c.get('modality')}

    weeks = []
    for template in phase.get('week_templates') or []:
        days = []
        for i, day in enumerate(template):
            spec = _day_spec(day)
            # week_template.plan_week's rule: the day says, else its first
            # category does, else it is warmed up.
            wants_warm = bool(spec and warm in categories) and (
                spec['warm_up'] if spec.get('warm_up') is not None
                else (categories.get(spec['categories'][0]) or {}).get('warm_up', True))
            days.append({'day': WEEKDAYS[i], 'rest': spec is None,
                         'pieces': [piece(c) for c in spec['categories']] if spec else [],
                         'warmUp': wants_warm, 'light': bool(spec and spec.get('light'))})
        weeks.append(days)
    return {'kind': 'template', 'weeks': weeks,
            'dropOrder': [piece(c)['name'] for c in phase.get('drop_order') or []],
            'warmUp': (categories.get(warm) or {}).get('name') if warm else None}


def _day_spec(day) -> dict | None:
    if day == 'rest':
        return None
    if isinstance(day, str):
        return {'categories': [day]}
    if isinstance(day, list):
        return {'categories': list(day)}
    return {'categories': list(day['categories']), 'warm_up': day.get('warm_up'), 'light': day.get('light')}


def _contract_items(blocks: list, exercises: dict) -> list[dict]:
    out = []
    for b in blocks:
        ex = exercises.get(b['exercise_id']) or {}
        out.append({'exercise': b['exercise_id'], 'name': ex.get('name') or words(b['exercise_id']),
                    'role': b.get('role'), 'prescription': prescription(b),
                    # A contract's load note is prose ("make it harder whenever…"), said with the notes.
                    'note': ' '.join(n.strip() for n in (b.get('load_note'), b.get('notes')) if n) or None,
                    'optional': bool(b.get('optional')),
                    'alternatives': [exercises.get(a, {}).get('name') or words(a)
                                     for a in _listify(b.get('alternatives'))]})
    return out


def _contract_week(phase: dict, contract: dict, exercises: dict, archetypes: dict) -> dict:
    modules = []
    for m in contract['modules']:
        run = training_contract.in_phase(m, phase['id'])
        if run is None:
            continue
        variants = [{'id': v['id'], 'name': v['name'], 'archetype': v.get('archetype_id'),
                     'items': _contract_items(v['blocks'], exercises)}
                    for v in m.get('variants') or []]
        by_days = m.get('exposures_by_days')
        modules.append({
            'id': m['id'], 'name': m['name'], 'modality': m['modality'],
            'archetype': m.get('archetype_id'),
            'archetypeName': (archetypes.get(m.get('archetype_id')) or {}).get('name'),
            'perWeek': run.get('exposures_per_week'),
            'perWeekByDays': {str(k): v for k, v in by_days.items()} if by_days else None,
            'levels': m.get('training_levels') or [],
            'optional': bool(m.get('optional')),
            'whenMastered': bool(m.get('when_mastered')),
            'requires': [exercises.get(e, {}).get('name') or words(e) for e in m.get('requires_mastery') or []],
            'maxRpe': m.get('max_rpe'),
            'progression': _PROGRESSION_WORDS.get(m['progression']['model'], words(m['progression']['model'])),
            'periods': [{'name': p.get('name') or words(p.get('id')), 'weeks': p['weeks'],
                         'deload': bool(p.get('deload'))} for p in m.get('periods') or [] if p.get('weeks')],
            'variants': variants,
            'items': [] if variants else _contract_items(m.get('blocks') or [], exercises),
            'advice': m.get('advice'),
        })
    return {'kind': 'contract', 'modules': modules}


def _framework_week(framework: dict) -> dict:
    per = framework.get('sessions_per_week') or {}
    return {'kind': 'framework',
            'sessions': [{'modality': m, 'perWeek': n} for m, n in per.items() if n]}


def week_mix(week: dict) -> dict[str, float]:
    """Sessions a week by modality. A template day of several pieces counts
    each as its share of the day; optional and gated contract modules are left
    out (the essential week); a template's weeks are averaged."""
    mix: dict[str, float] = {}
    if week['kind'] == 'template':
        for days in week['weeks']:
            for d in days:
                for p in d['pieces']:
                    if p['modality']:
                        mix[p['modality']] = mix.get(p['modality'], 0) + 1 / len(d['pieces']) / len(week['weeks'])
    elif week['kind'] == 'contract':
        for m in week['modules']:
            if not m['optional'] and not m['whenMastered'] and m['perWeek']:
                mix[m['modality']] = mix.get(m['modality'], 0) + m['perWeek']
    else:
        for s in week['sessions']:
            mix[s['modality']] = mix.get(s['modality'], 0) + s['perWeek']
    return mix


def _mix_list(mix: dict[str, float]) -> list[dict]:
    total = sum(mix.values()) or 1
    return [{'modality': m, 'perWeek': round(n, 2), 'share': round(n / total, 3)}
            for m, n in sorted(mix.items(), key=lambda kv: (-kv[1], kv[0]))]


# ─── Phases and tracks ───────────────────────────────────────────────────────

def _tests(phase: dict, archetypes: dict, standards: dict) -> list[dict]:
    out = []
    for t in phase.get('tests') or []:
        ids = _listify(t.get('archetypes') or t.get('archetype'))
        if 'every' in t:
            when = f"every {t['every']} weeks"
        else:
            w = t.get('week', 'first')
            when = {'first': 'the first week', 'last': 'the last week'}.get(w, f'week {w}')
        names, measures = [], []
        for aid in ids:
            arch = archetypes.get(aid) or {}
            names.append(arch.get('name') or words(aid))
            for slot in arch.get('slots') or []:
                std = slot.get('standard')
                sid = std.get('id') if isinstance(std, dict) else std
                if sid:
                    name = (standards.get(sid) or {}).get('name') or words(sid)
                    if name not in measures:
                        measures.append(name)
        out.append({'when': when, 'sessions': names, 'standards': measures,
                    'onDeload': bool(t.get('on_deload'))})
    return out


def _deload(framework: dict) -> str | None:
    d = framework.get('deload_protocol')
    if not d or not d.get('frequency_weeks'):
        return None
    keep = d.get('volume_reduction_pct')
    kept = f', keeping {round(keep * 100)} % of the volume' if keep is not None else ''
    return f"Every {d['frequency_weeks']} weeks an easier week{kept}."


def _phase(phase: dict, framework: dict, contract: dict | None, archetypes: dict,
           exercises: dict, standards: dict) -> dict:
    if contract:
        week = _contract_week(phase, contract, exercises, archetypes)
    elif phase.get('week_templates'):
        week = _template_week(phase, framework)
    else:
        week = _framework_week(framework)
    exp = framework.get('expectations') or {}
    mix = week_mix(week)
    days = None
    days_per_week = exp.get('ideal_days_per_week')
    if week['kind'] == 'template' and week['weeks']:
        # The source's first week, day by day: its modalities, None for rest.
        days = [None if d['rest'] else [p['modality'] for p in d['pieces']] for d in week['weeks'][0]]
        days_per_week = round(sum(sum(not d['rest'] for d in w) for w in week['weeks']) / len(week['weeks']), 1)
    return {
        'id': phase['id'], 'name': phase.get('name') or words(phase['id']), 'kind': phase.get('kind'),
        'weeks': phase.get('weeks'), 'repeatable': bool(phase.get('repeatable')),
        # At a glance, the same keys for every phase however it is built.
        'days': days,
        'daysPerWeek': days_per_week,
        'minutes': exp.get('ideal_session_minutes'),
        'sessionsPerWeek': round(sum(mix.values()), 1),
        'framework': {'id': framework.get('id'), 'name': framework.get('name')},
        'focus': phase.get('focus'), 'description': (phase.get('description') or '').strip() or None,
        'adaptations': phase.get('adaptations') or [], 'intensity': phase.get('intensity'),
        'intensitySplit': framework.get('intensity_distribution') or {},
        'deload': None if contract else _deload(framework),
        'tests': _tests(phase, archetypes, standards),
        'notYet': [exercises.get(e, {}).get('name') or words(e) for e in phase.get('exclude_exercises') or []],
        'week': week,
        'mix': _mix_list(mix),
    }


def _track_levels(phil: dict, track: dict, contract: dict | None, frameworks: dict) -> list[str]:
    if contract:
        return list(contract.get('training_levels') or [])
    levels: list[str] = []
    for ph in track.get('phases') or []:
        aw = (frameworks.get(ph.get('framework_id')) or {}).get('applicable_when') or {}
        for lvl in _listify(aw.get('training_level')):
            if lvl not in levels:
                levels.append(lvl)
    return levels


def _track(phil: dict, track: dict, contract: dict | None, frameworks: dict, archetypes: dict,
           exercises: dict, standards: dict) -> dict:
    phase_docs = [_phase(ph, frameworks.get(ph['framework_id']) or {}, contract, archetypes, exercises, standards)
                  for ph in track.get('phases') or []]
    weeks = sum(p['weeks'] or 0 for p in phase_docs)
    mix: dict[str, float] = {}
    intensity: dict[str, float] = {}
    for p in phase_docs:
        share = (p['weeks'] or 0) / (weeks or 1)
        for row in p['mix']:
            mix[row['modality']] = mix.get(row['modality'], 0) + row['perWeek'] * share
        for bucket, pct in p['intensitySplit'].items():
            intensity[bucket] = intensity.get(bucket, 0) + pct * share
    goals: list[str] = []
    for p in phase_docs:
        goals += [a for a in p['adaptations'] if a not in goals]
    requires = []
    for m in (contract or {}).get('modules') or []:
        if not m.get('when_mastered'):
            requires += [e for e in m.get('requires_mastery') or [] if e not in requires]
    primary = phases.primary_track(phil)
    return {
        'id': track['id'], 'name': track.get('name') or words(track['id']),
        'description': (track.get('description') or '').strip() or None,
        'primary': bool(primary and primary['id'] == track['id']),
        'forLevels': [lvl for lvl, tid in (phil.get('track_for_level') or {}).items() if tid == track['id']],
        'levels': _track_levels(phil, track, contract, frameworks),
        'builtBy': 'contract' if contract else (
            'template' if any(ph.get('week_templates') for ph in track.get('phases') or []) else 'framework'),
        'weeks': weeks,
        'repeatable': len(phase_docs) == 1 and phase_docs[0]['repeatable'],
        'notes': ((contract or {}).get('notes') or '').strip() or None,
        'kettlebellPair': bool(contract and contract.get('requires_kettlebell_pair')),
        'mix': _mix_list(mix),
        'intensity': {k: round(v, 3) for k, v in intensity.items() if v},
        'daysPerWeek': _span(p['daysPerWeek'] for p in phase_docs),
        'minutes': _span(p['minutes'] for p in phase_docs),
        'tests': sum(len(p['tests']) for p in phase_docs),
        'goals': goals,
        'requires': [exercises.get(e, {}).get('name') or words(e) for e in requires],
        'phases': phase_docs,
    }


def _span(values) -> dict | None:
    vals = [v for v in values if v is not None]
    return {'min': min(vals), 'max': max(vals)} if vals else None


# ─── Sessions ────────────────────────────────────────────────────────────────

def _session(arch: dict, exercises: dict, policy) -> dict:
    slots = []
    for slot in arch.get('slots') or []:
        pool, listed = slot_exercises(slot, arch.get('modality'), exercises, policy)
        std = slot.get('standard')
        slots.append({
            'role': slot.get('role'), 'name': words(slot.get('role')),
            'slotType': slot.get('slot_type'), 'prescription': prescription(slot),
            'note': slot.get('notes'), 'parent': slot.get('parent_slot_role'),
            'listed': listed, 'technique': bool(slot.get('skip_exercise')),
            'standard': (std.get('id') if isinstance(std, dict) else std) or None,
            'exercises': [{'id': ex['id'], 'name': ex.get('name') or words(ex['id'])} for ex in pool],
        })
    return {
        'id': arch['id'], 'name': arch.get('name') or words(arch['id']), 'modality': arch.get('modality'),
        'minutes': arch.get('duration_estimate_minutes'), 'levels': arch.get('training_levels') or [],
        'test': bool(arch.get('test')), 'note': (arch.get('notes') or '').strip() or None,
        'equipment': [words(e) for e in _listify(arch.get('required_equipment')) if e != 'open_space'],
        'slots': slots,
    }


def _sessions(phil: dict, track_docs: list, framework_ids: list, frameworks: dict,
              package_archetypes: list, exercises: dict, philosophies: dict) -> dict:
    """Every session the package writes, in groups a reader recognises: a
    template's categories (in the source's order), a contract's modules, then
    the rest by modality; the tests apart."""
    policy = policy_for(phil['id'], philosophies)
    by_id = {a['id']: a for a in package_archetypes}
    placed: set = set()
    groups = []
    for fid in framework_ids:
        fw = frameworks.get(fid) or {}
        for cid, cat in (fw.get('categories') or {}).items():
            ids = [a for a in cat.get('archetypes') or [] if a in by_id and a not in placed]
            if not ids:
                continue
            placed.update(ids)
            groups.append({'kind': 'category', 'id': cid, 'name': cat.get('name') or words(cid),
                           'modality': cat.get('modality'), 'advice': cat.get('advice'),
                           'warmUp': cid == fw.get('warm_up_category'), 'sessions': ids})
    for t in track_docs:
        for p in t['phases']:
            if p['week']['kind'] != 'contract':
                continue
            for m in p['week']['modules']:
                ids = [a for a in dict.fromkeys([m['archetype'], *(v['archetype'] for v in m['variants'])])
                       if a in by_id and a not in placed]
                if ids:
                    placed.update(ids)
                    groups.append({'kind': 'module', 'id': m['id'], 'name': m['name'],
                                   'modality': m['modality'], 'advice': m['advice'], 'warmUp': False,
                                   'sessions': ids})
    tests = [a['id'] for a in package_archetypes if a.get('test') and a['id'] not in placed]
    placed.update(tests)
    by_modality: dict = {}
    for a in package_archetypes:
        if a['id'] not in placed:
            by_modality.setdefault(a.get('modality'), []).append(a['id'])
    for mod, ids in sorted(by_modality.items(), key=lambda kv: -len(kv[1])):
        groups.append({'kind': 'modality', 'id': mod, 'name': None, 'modality': mod, 'advice': None,
                       'warmUp': False, 'sessions': ids})
    if tests:
        groups.append({'kind': 'tests', 'id': 'tests', 'name': 'Tests', 'modality': None, 'advice': None,
                       'warmUp': False, 'sessions': tests})
    return {'groups': groups,
            'sessions': {a['id']: _session(a, exercises, policy) for a in package_archetypes}}


# ─── The record ──────────────────────────────────────────────────────────────

def _record(phil_id: str) -> dict | None:
    path = os.path.join(loader._PACKAGES_DIR, phil_id, 'fidelity.yaml')
    return loader._load_yaml(path) if os.path.exists(path) else None


def _source_line(s: dict) -> str:
    who = s.get('author')
    return f"{s['title']} — {who}" if who and s.get('title') else (s.get('title') or who or s.get('id', ''))


def _rules(record: dict | None) -> dict:
    if not record:
        return {'sources': [], 'rules': [], 'inventions': [], 'open': []}
    sources = {s['id']: s for s in record.get('sources') or []}
    return {
        'sources': [{'id': s['id'], 'title': _source_line(s), 'where': s.get('where'), 'kind': s.get('kind'),
                     'read': s.get('read'), 'published': s.get('published')} for s in sources.values()],
        'rules': [{'id': r['id'], 'text': r['text'],
                   'cites': [{'source': _source_line(sources.get(c.get('source')) or {'title': c.get('source')}),
                              'quote': c.get('at')} for c in r.get('cites') or []]}
                  for r in record.get('rules') or []],
        'inventions': [{'id': i['id'], 'text': i['text']} for i in record.get('inventions') or []],
        'open': list(record.get('open') or []),
    }


# ─── The document ────────────────────────────────────────────────────────────

def _core(phil: dict, *, frameworks: dict, archetypes: list, exercises: dict, contracts: dict,
          record: dict | None, standards: dict) -> dict:
    """Everything but the session catalogue: cheap enough to build for every
    philosophy at once (the landing, and comparing)."""
    arch_by_id = {a['id']: a for a in archetypes}
    track_docs = [_track(phil, t, contracts.get(t['id']), frameworks, arch_by_id, exercises, standards)
                  for t in phases.tracks_of(phil)]
    primary = next((t for t in track_docs if t['primary']), track_docs[0] if track_docs else None)
    main_fw = frameworks.get(goals._main_framework(phases.primary_track(phil)) or '') if track_docs else None
    expectations = phil.get('expectations') or (main_fw or {}).get('expectations')
    rules = _rules(record)
    levels = []
    for t in track_docs:
        levels += [lvl for lvl in t['levels'] if lvl not in levels]
    order = ('novice', 'intermediate', 'advanced', 'elite')
    return {
        'id': phil['id'],
        'name': phil.get('name') or words(phil['id']),
        'summary': (phil.get('notes') or '').strip() or None,
        'accent': (phil.get('bias') or [None])[0],
        'bias': list(phil.get('bias') or []),
        'scope': list(phil.get('scope') or []),
        'avoidWith': list(phil.get('avoid_with') or []),
        'principles': [words(p) for p in phil.get('core_principles') or []],
        'models': {'intensity': words(phil.get('intensity_model')) or None,
                   'progression': words(phil.get('progression_philosophy')) or None},
        'levels': sorted(levels, key=lambda lvl: order.index(lvl) if lvl in order else len(order)),
        'equipment': [{'id': e, 'name': words(e)} for e in phil.get('required_equipment') or []
                      if e != 'open_space'],
        'expectations': expectations,
        'primaryTrackId': primary['id'] if primary else None,
        'mix': primary['mix'] if primary else [],
        'tracks': track_docs,
        'borrows': [{'package': b.get('package'), 'label': b.get('label') or words(b.get('package')),
                     'reason': (b.get('reason') or '').strip() or None, 'modalities': b.get('modalities') or []}
                    for b in (phil.get('borrows_from') or []) if isinstance(b, dict)],
        'sources': rules['sources'] or [{'id': None, 'title': s, 'where': None, 'kind': None, 'read': None,
                                         'published': None} for s in phil.get('sources') or []],
        'rules': rules['rules'],
        'inventions': rules['inventions'],
        'open': rules['open'],
        'sessionCount': sum(1 for a in archetypes if a.get('_package') == phil['id']),
    }


def measures_of(spec: dict | None) -> dict:
    """What progress means for the method (its analytics spec's headline) and
    the standards it is measured by, each with its modality (`domain`)."""
    if not spec:
        return {'headline': None, 'signals': 0, 'standards': []}
    head = next((e for e in spec.get('progress') or [] if e.get('headline')), None)
    return {'headline': head['label'] if head else None, 'signals': len(spec.get('progress') or []),
            'standards': [{'id': b['id'], 'name': b['name'], 'domain': b.get('domain')}
                          for b in spec.get('benchmarks') or []]}


def glance(core: dict, measures: dict | None = None) -> dict:
    """The comparable facts: the same keys for every philosophy, numbers and
    ids rather than prose, so a header, a landing card or a side-by-side
    comparison reads them alike. Tracks keep their phases' glance fields."""
    exp = core['expectations'] or {}
    primary = next((t for t in core['tracks'] if t['id'] == core['primaryTrackId']), None)
    standards: list[str] = []
    for t in core['tracks']:
        for p in t['phases']:
            for test in p['tests']:
                standards += [n for n in test['standards'] if n not in standards]
    phase_keys = ('id', 'name', 'kind', 'weeks', 'repeatable', 'focus', 'days', 'daysPerWeek', 'minutes',
                  'sessionsPerWeek', 'mix', 'intensitySplit')
    return {
        'id': core['id'], 'name': core['name'], 'accent': core['accent'], 'bias': core['bias'],
        'levels': core['levels'],
        'weeks': {'min': exp.get('min_weeks'), 'ideal': exp.get('ideal_weeks')} if exp else None,
        'daysPerWeek': {'min': exp.get('min_days_per_week'), 'ideal': exp.get('ideal_days_per_week')} if exp else None,
        'sessionMinutes': {'min': exp.get('min_session_minutes'), 'ideal': exp.get('ideal_session_minutes')} if exp else None,
        'longSessionMinutes': exp.get('ideal_long_session_minutes'),
        'equipment': core['equipment'],
        'primaryTrackId': core['primaryTrackId'],
        'mix': core['mix'],
        'intensity': primary['intensity'] if primary else {},
        'tested': standards,
        'measures': measures or measures_of(None),
        'counts': {'tracks': len(core['tracks']), 'rules': len(core['rules']), 'sources': len(core['sources']),
                   'inventions': len(core['inventions']), 'open': len(core['open']),
                   'sessions': core['sessionCount']},
        'tracks': [{**{k: t[k] for k in ('id', 'name', 'primary', 'forLevels', 'levels', 'builtBy', 'weeks',
                                        'repeatable', 'kettlebellPair', 'requires', 'daysPerWeek', 'minutes',
                                        'mix', 'intensity', 'tests', 'goals')},
                    'phases': [{k: p[k] for k in phase_keys} | {'tests': len(p['tests'])} for p in t['phases']]}
                   for t in core['tracks']],
    }


def build(phil: dict, *, philosophies: list, frameworks: dict, modalities: dict, archetypes: list,
          exercises: dict, contracts: dict, record: dict | None, standards: dict,
          measures: dict | None = None) -> dict:
    """`contracts`: track id → the loaded training contract, for the tracks
    that have one."""
    core = _core(phil, frameworks=frameworks, archetypes=archetypes, exercises=exercises, contracts=contracts,
                 record=record, standards=standards)
    package_archetypes = [a for a in archetypes if a.get('_package') == phil['id']]
    return {**core, 'glance': glance(core, measures),
            **_sessions(phil, core['tracks'], phases.framework_ids_of(phil), frameworks, package_archetypes,
                        exercises, {p['id']: p for p in philosophies})}


_CACHE: dict = {}
_GLANCES: list | None = None
_DATA: dict | None = None


def clear_cache() -> None:
    """An authoring write changed the packages (api.clear_static_cache)."""
    global _GLANCES, _DATA
    _CACHE.clear()
    _GLANCES = None
    _DATA = None


def _specs() -> dict:
    data = _loaded()
    if data['specs'] is None:
        from src.analytics.describe import describe_all
        data['specs'] = describe_all()['philosophies']
    return data['specs']


def _loaded() -> dict:
    """The package data, read once: every describe and the glances read the
    same lists, which they never change."""
    global _DATA
    if _DATA is None:
        exercises, _ = loader.load_all_exercises()
        _DATA = {'philosophies': loader.load_philosophies(), 'frameworks': loader.load_all_frameworks(),
                 'modalities': loader.load_all_modalities(), 'archetypes': loader.load_all_archetypes(),
                 'exercises': exercises, 'standards': benchmarks_data.by_id(), 'specs': None}
    return _DATA


def _contracts(phil: dict) -> dict:
    out = {}
    for t in phases.tracks_of(phil):
        c = training_contract.load_contract(phil['id'], t['id'])
        if c:
            out[t['id']] = c
    return out


def describe(phil_id: str) -> dict | None:
    """The document for one philosophy, built once per process (package data
    changes only with a deploy); None for an unknown id."""
    if phil_id in _CACHE:
        return _CACHE[phil_id]
    data = _loaded()
    phil = next((p for p in data['philosophies'] if p['id'] == phil_id), None)
    if phil is None:
        return None
    doc = build(phil, philosophies=data['philosophies'], frameworks=data['frameworks'],
                modalities=data['modalities'], archetypes=data['archetypes'], exercises=data['exercises'],
                standards=data['standards'], contracts=_contracts(phil), record=_record(phil_id),
                measures=measures_of(_specs().get(phil_id)))
    _CACHE[phil_id] = doc
    return doc


def glance_all() -> list[dict]:
    """Every philosophy's glance, in the loader's order; built once."""
    global _GLANCES
    if _GLANCES is None:
        data, specs = _loaded(), _specs()
        _GLANCES = [glance(_core(phil, frameworks=data['frameworks'], archetypes=data['archetypes'],
                                 exercises=data['exercises'], contracts=_contracts(phil),
                                 record=_record(phil['id']), standards=data['standards']),
                           measures_of(specs.get(phil['id'])))
                    for phil in data['philosophies']]
    return _GLANCES
