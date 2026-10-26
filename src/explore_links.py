"""How Explore's levels connect: Philosophy → Framework → Modality → Archetype →
Exercise → Movement, and which exercise leads to which.

Explore's details show what leads into each entity and what follows from it.
The links are computed here, with the selector's own rules, because the obvious
client reading is wrong: 1,748 of the 1,762 slot filters name their exercises
by `exercise_ids`, which the web's slot matcher never read, so an exercise
looked used by almost nothing. A movement is a pattern exercises declare
(`movement_patterns`), not one of the slot-filter aliases in
`data/commons/movement_patterns.yaml`, which group them.

`requires` and `unlocks` describe one graph from both ends and disagree (31
pairs are written on both sides, 53 on one only), so the progression is their
union; a `requires` entry that is no exercise is a concept the athlete brings
(`bracing_mechanics`), kept apart.

Pure over the loaded data: `build(...)` takes the lists, `build_from_loader()`
reads them.
"""
from __future__ import annotations

from src import loader, provenance
from src.analytics.movement import ROLLUPS
from src.selector import _PATTERN_ALIASES, _matches_slot_filter

_TIERS = ('committed', 'core', 'supplementary')


def movement_name(pattern: str) -> str:
    return pattern.replace('_', ' ').capitalize()


def _listify(value) -> list:
    if value is None:
        return []
    return [value] if isinstance(value, str) else list(value)


def _philosophy_frameworks(philosophies: list, frameworks: dict) -> list:
    edges: dict = {}
    for p in philosophies:
        pid = p['id']
        for fw in frameworks.values():
            if fw.get('source_philosophy') == pid:
                edges.setdefault((pid, fw['id']), [])
        for track_index, track in enumerate(p.get('tracks') or []):
            for order, phase in enumerate(track.get('phases') or []):
                fid = phase.get('framework_id')
                if fid not in frameworks:
                    continue
                edges.setdefault((pid, fid), []).append({
                    'trackId': track.get('id'), 'trackName': track.get('name', track.get('id')),
                    'trackIndex': track_index,
                    'phaseId': phase.get('id'), 'phaseName': phase.get('name', phase.get('id')),
                    'order': order,
                })
    return [{'philosophy': pid, 'framework': fid,
             'owner': frameworks[fid].get('source_philosophy') == pid, 'phases': phases}
            for (pid, fid), phases in edges.items()]


def _framework_modalities(frameworks: dict, modalities: dict) -> list:
    out = []
    for fw in frameworks.values():
        per_week = fw.get('sessions_per_week') or {}
        priority = fw.get('modality_priority') or {}
        tier_of = {m: t for t in _TIERS for m in _listify(priority.get(t))}
        for mod in dict.fromkeys([*per_week, *tier_of]):
            if mod not in modalities:
                continue
            out.append({'framework': fw['id'], 'modality': mod,
                        'sessionsPerWeek': per_week.get(mod), 'tier': tier_of.get(mod)})
    return out


def _policy(pkg: str | None, philosophies: dict) -> provenance.SourcePolicy:
    # provenance.resolve_source_policy, from the philosophies already loaded.
    if not pkg:
        return provenance.SourcePolicy()
    phil = philosophies.get(pkg) or {}
    return provenance.SourcePolicy(owner_packages=frozenset({pkg}),
                                   borrows=provenance._parse_borrows(phil) if phil else {})


def _archetype_exercises(archetypes: list, exercises: dict, philosophies: list) -> list:
    by_id = {p['id']: p for p in philosophies}
    policies: dict = {}
    out = []
    for arch in archetypes:
        pkg = arch.get('_package')
        if pkg not in policies:
            policies[pkg] = _policy(pkg, by_id)
        policy = policies[pkg]
        modality = arch.get('modality')
        found: dict = {}
        for slot in arch.get('slots') or []:
            if slot.get('skip_exercise'):
                continue
            ex_filter = slot.get('exercise_filter') or {}
            listed = ex_filter.get('exercise_ids') or []
            # A listed slot can only take what it lists; a filter slot reads them all.
            pool = [exercises[i] for i in listed if i in exercises] if listed else exercises.values()
            for ex in pool:
                # A test's own exercise or a named workout's movement is taken
                # only by a slot that names it (selector.select_exercise).
                if (ex.get('test_only') or ex.get('named_only')) and ex['id'] not in listed:
                    continue
                if not provenance.allows_exercise(ex, policy, modality):
                    continue
                if not _matches_slot_filter(ex, ex_filter, set()):
                    continue
                edge = found.setdefault(ex['id'], {'archetype': arch['id'], 'exercise': ex['id'],
                                                   'slots': [], 'via': 'listed' if listed else 'filter'})
                role = slot.get('role')
                if role and role not in edge['slots']:
                    edge['slots'].append(role)
                if listed:
                    edge['via'] = 'listed'
        out.extend(found.values())
    return out


def _progression(exercises: dict) -> tuple[list, list]:
    edges: dict = {}
    concepts = []
    for ex in exercises.values():
        for req in _listify(ex.get('requires')):
            if req in exercises:
                edges.setdefault((req, ex['id']), set()).add('requires')
            else:
                concepts.append({'exercise': ex['id'], 'concept': req})
        for nxt in _listify(ex.get('unlocks')):
            if nxt in exercises:
                edges.setdefault((ex['id'], nxt), set()).add('unlocks')
    return ([{'from': a, 'to': b, 'declaredBy': sorted(by)} for (a, b), by in edges.items() if a != b],
            concepts)


def _movements(exercises: dict) -> tuple[list, list]:
    counts: dict = {}
    edges = []
    for ex in exercises.values():
        for pat in dict.fromkeys(_listify(ex.get('movement_patterns'))):
            counts[pat] = counts.get(pat, 0) + 1
            edges.append({'exercise': ex['id'], 'movement': pat})
    rollup_of = {p: name for name, pats in ROLLUPS.items() for p in pats}
    movements = []
    for pat in sorted(counts):
        groups = [alias for alias, (mode, pats) in _PATTERN_ALIASES.items()
                  if mode in ('or', 'and') and pat in pats and alias != pat]
        movements.append({'id': pat, 'name': movement_name(pat), 'exerciseCount': counts[pat],
                          'filterGroups': groups, 'rollup': rollup_of.get(pat)})
    return movements, edges


def build(philosophies: list, frameworks: dict, modalities: dict,
          archetypes: list, exercises: dict) -> dict:
    movements, exercise_movement = _movements(exercises)
    progression, concepts = _progression(exercises)
    return {
        'movements': movements,
        'links': {
            'philosophyFramework': _philosophy_frameworks(philosophies, frameworks),
            'frameworkModality': _framework_modalities(frameworks, modalities),
            'modalityArchetype': [{'modality': a.get('modality'), 'archetype': a['id'],
                                   'package': a.get('_package')}
                                  for a in archetypes if a.get('modality') in modalities],
            'archetypeExercise': _archetype_exercises(archetypes, exercises, philosophies),
            'exerciseMovement': exercise_movement,
            'exerciseProgression': progression,
            'exerciseConcepts': concepts,
        },
    }


def build_from_loader() -> dict:
    exercises, _ = loader.load_all_exercises()
    return build(loader.load_philosophies(), loader.load_all_frameworks(),
                 loader.load_all_modalities(), loader.load_all_archetypes(), exercises)
