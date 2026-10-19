"""Weeks the source writes day by day (Horsemen's month templates).

A phase may declare `week_templates`: seven days per week of the phase, each
`rest` or one or more day categories of its framework (`categories`). A
category is a pool of named workouts taken in rotation, and the day's session
is the next one the athlete can do as written — level, equipment, injuries,
time — opened by a workout from the framework's `warm_up_category`. Nothing
here scales a workout: one that does not fit is passed over for the next, then
for the category's declared `fallback`, and the week says so.

The days keep their template positions (the source's six days and a rest day
on the seventh); with fewer training days the phase's `drop_order` says which
go first, and the athlete's preferred and forced-rest days are honoured.
"""
from __future__ import annotations

from copy import deepcopy

REST = 'rest'
# About a week of picks: six days, each a workout and its warm-up.
RECENT = 14


def day_spec(day) -> dict | None:
    """One template day as {categories, warm_up, light}; None for rest."""
    if day == REST:
        return None
    if isinstance(day, str):
        return {'categories': [day], 'warm_up': None, 'light': False}
    if isinstance(day, list):
        return {'categories': list(day), 'warm_up': None, 'light': False}
    return {'categories': list(day['categories']), 'warm_up': day.get('warm_up'),
            'light': bool(day.get('light'))}


def training_days(template: list, days_per_week: int, drop_order: list,
                  categories: dict) -> tuple[list[tuple[int, dict]], list[str]]:
    """The template's training days the athlete keeps, as (weekday 1-7, spec),
    and what was left out. A day goes when its first category is the next in
    `drop_order`, the week's last such day first; past the list, the last day."""
    kept = [(i + 1, spec) for i, spec in enumerate(day_spec(d) for d in template) if spec]
    dropped = []
    while len(kept) > max(1, days_per_week):
        index = None
        for cat in drop_order:
            hits = [k for k, (_, spec) in enumerate(kept) if spec['categories'][0] == cat]
            if hits:
                index = hits[-1]
                break
        if index is None:
            index = len(kept) - 1
        _, spec = kept.pop(index)
        dropped.append(' + '.join(categories.get(c, {}).get('name', c) for c in spec['categories']))
    return kept, dropped


def place_days(kept: list[tuple[int, dict]], preferred: list[int], forced_rest: list[int]) -> list[tuple[int, dict]]:
    """Weekdays for the kept days: the athlete's preferred days when they name
    as many, else each day's template position, moved off a forced rest day to
    the nearest free one."""
    if preferred and len(preferred) >= len(kept):
        return [(d, spec) for d, (_, spec) in zip(sorted(preferred)[:len(kept)], kept)]
    taken: set[int] = set()
    out = []
    for position, spec in kept:
        day = position
        if day in forced_rest or day in taken:
            free = [d for d in range(1, 8) if d not in forced_rest and d not in taken
                    and d not in {p for p, _ in kept if p != position}]
            if free:
                day = min(free, key=lambda d: (abs(d - position), d))
        taken.add(day)
        out.append((day, spec))
    return sorted(out, key=lambda x: x[0])


def _prefixed(arch: dict, prefix: str, note: str = '', light: bool = False) -> list[dict]:
    slots = []
    for slot in arch.get('slots') or []:
        slot = deepcopy(slot)
        if prefix:
            slot['role'] = prefix + slot['role']
            if slot.get('parent_slot_role'):
                slot['parent_slot_role'] = prefix + slot['parent_slot_role']
        if note:
            slot['notes'] = f"{note}{slot.get('notes') or ''}".strip()
        if light and slot.get('slot_type') not in ('time_domain', 'distance', 'skill_practice'):
            written = slot.get('load')
            slot['load'] = 'Light, work on form' + (f' (written: {written})' if written else '')
        slots.append(slot)
    return slots


def compose(pieces: list[tuple[str, dict]], warm: dict | None, light: bool, categories: dict) -> dict:
    """One session's archetype: the warm-up's slots, then each piece's in the
    day's order. Its id is the first piece's, so rotation, history and the
    analytics read the day's named workout."""
    main = pieces[0][1]
    slots = []
    if warm:
        slots += _prefixed(warm, 'warm_up_', f"Warm-up ({warm['name']}). ")
    for k, (_, arch) in enumerate(pieces):
        slots += _prefixed(arch, '' if k == 0 else f"{arch['id']}_",
                           f"{arch['name']}: " if len(pieces) > 1 else '', light)
    minutes = sum(a.get('duration_estimate_minutes') or 0 for _, a in pieces) + \
        ((warm or {}).get('duration_estimate_minutes') or 0)
    composed = {**main, 'name': ' + '.join(a['name'] for _, a in pieces), 'slots': slots,
                'duration_estimate_minutes': minutes,
                'required_equipment': sorted({e for _, a in pieces for e in a.get('required_equipment') or []}
                                             | set((warm or {}).get('required_equipment') or []))}
    return composed


def plan_week(entry: dict, framework: dict, constraints: dict, archetypes: dict,
              rotation: dict, fits, recent: list | None = None,
              left_out: dict | None = None) -> tuple[dict, list[str]]:
    """The week's sessions, {weekday: [session]}, and its compromises.

    `archetypes` is the allowed library by id, `rotation` each category's next
    position (kept across weeks by the caller), `fits(arch, minutes)` whether
    the athlete can do an archetype as written in that many minutes, and
    `recent` the last week or so of picks (kept by the
    caller): a workout two pools share is not repeated within a week while
    another fits. `left_out` collects the days nothing fitted, {weekday:
    category}, where a phase's test may still go."""
    recent = recent if recent is not None else []
    categories = framework.get('categories') or {}
    days = constraints.get('days_per_week', 6)
    kept, dropped = training_days(entry['week_template'], days, entry.get('drop_order') or [], categories)
    notes = []
    if dropped:
        notes.append(f"With {days} training days the week leaves out: {', '.join(dropped)} "
                     f"(the source trains {len(kept) + len(dropped)} days).")
    total = len([d for d in entry['week_template'] if d != REST])
    if days > total:
        notes.append(f"The source trains {total} days a week and rests the others; "
                     f"{days - total} of your days stay rest days.")
    placed = place_days(kept, sorted(constraints.get('preferred_days') or []),
                        sorted(constraints.get('forced_rest_days') or []))
    cap = constraints.get('session_time_minutes', 60)
    day_configs = constraints.get('day_configs') or {}
    warm_cat = framework.get('warm_up_category')
    schedule: dict = {}

    def pick(cat: str, minutes: float, seen: set) -> tuple[str, dict] | None:
        spec = categories.get(cat)
        if spec is None or cat in seen:
            return None
        seen.add(cat)
        pool = [aid for aid in spec['archetypes'] if aid in archetypes]
        start = rotation.get(cat, 0)
        for fresh_only in (True, False):
            for k in range(len(pool)):
                aid = pool[(start + k) % len(pool)]
                if fresh_only and aid in recent[-RECENT:]:
                    continue
                if fits(archetypes[aid], minutes):
                    rotation[cat] = (start + k + 1) % len(pool)
                    recent.append(aid)
                    return cat, archetypes[aid]
        for other in spec.get('fallback') or []:
            found = pick(other, minutes, seen)
            if found:
                notes.append(f"No {spec['name']} workout fits as written (equipment, injuries or "
                             f"{minutes:g} minutes); {categories[found[0]]['name']} in its place.")
                return found
        return None

    for day, spec in placed:
        limit = min(cap, (day_configs.get(day) or {}).get('minutes', cap))
        warm_spec = categories.get(warm_cat) if warm_cat else None
        wants_warm = spec['warm_up'] if spec['warm_up'] is not None else \
            all(categories.get(c, {}).get('warm_up', True) for c in spec['categories'][:1])
        warm_min = min((archetypes[a].get('duration_estimate_minutes') or 0
                        for a in (warm_spec or {}).get('archetypes', []) if a in archetypes), default=0)
        pieces = []
        left = limit - (warm_min if wants_warm and warm_spec else 0)
        for cat in spec['categories']:
            found = pick(cat, left, set())
            if found is None and wants_warm and warm_spec and not pieces:
                # The day's workout before its warm-up: without room for both,
                # the athlete warms up on their own.
                found = pick(cat, limit, set())
                if found is not None:
                    wants_warm = False
                    left = limit
                    notes.append(f"{found[1]['name']} fills {limit:g} minutes; its day has no "
                                 'warm-up from the list — warm up on your own.')
            if found is None:
                name = categories.get(cat, {}).get('name', cat)
                notes.append(f"No {name} workout fits as written (equipment, injuries or {left:g} minutes); "
                             + (f"the day does {pieces[0][1]['name']} alone." if pieces else 'the day is left out.'))
                continue
            pieces.append(found)
            left -= found[1].get('duration_estimate_minutes') or 0
        if not pieces:
            if left_out is not None:
                left_out[day] = spec['categories'][0]
            continue
        warm = None
        if wants_warm and warm_spec:
            found = pick(warm_cat, limit - sum(a.get('duration_estimate_minutes') or 0 for _, a in pieces), set())
            warm = found[1] if found else None
            if warm is None:
                notes.append(f"No warm-up fits in {limit:g} minutes beside the day's workout; warm up on your own.")
        cat = pieces[0][0]
        schedule[day] = [{
            'modality': categories[cat]['modality'],
            'category': cat,
            'category_name': ' + '.join(categories[c]['name'] for c, _ in pieces),
            'pieces': [{'category': c, 'archetype_id': a['id'], 'name': a['name']} for c, a in pieces],
            **({'warm_up': {'archetype_id': warm['id'], 'name': warm['name']}} if warm else {}),
            **({'light': True} if spec['light'] else {}),
            '_forced_archetype': compose(pieces, warm, spec['light'], categories),
        }]
    return schedule, list(dict.fromkeys(notes))


def prior_rotation(phase_sequence: list, first_entry: dict, frameworks: dict) -> dict:
    """Where each category's rotation stands at the first generated week: the
    days of every template week the track ran before it, counted as written.
    A regenerate from tomorrow then carries on through the pools instead of
    starting each one over at its first workout."""
    counts: dict = {}
    target = first_entry.get('phase_id')
    for ph in phase_sequence or []:
        templates = ph.get('week_templates') or []
        weeks = (first_entry.get('week_in_phase', 1) - 1) if ph.get('phase_id') == target else int(ph.get('weeks') or 1)
        fw = frameworks.get(ph.get('framework_id')) or {}
        categories = fw.get('categories') or {}
        for k in range(weeks if templates else 0):
            for day in templates[k % len(templates)]:
                spec = day_spec(day)
                if not spec:
                    continue
                for cat in spec['categories']:
                    counts[cat] = counts.get(cat, 0) + 1
                warm = spec['warm_up'] if spec['warm_up'] is not None else \
                    categories.get(spec['categories'][0], {}).get('warm_up', True)
                if warm and fw.get('warm_up_category'):
                    counts[fw['warm_up_category']] = counts.get(fw['warm_up_category'], 0) + 1
        if ph.get('phase_id') == target:
            break
    pools = {cid: len(c['archetypes']) for fw in frameworks.values() for cid, c in (fw.get('categories') or {}).items()}
    return {cat: n % pools[cat] for cat, n in counts.items() if pools.get(cat)}
