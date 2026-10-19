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


def place_days(kept: list[tuple[int, dict]], preferred: list[int], forced_rest: list[int],
               minutes: dict | None = None, is_long=lambda spec: False) -> list[tuple[int, dict]]:
    """Weekdays for the kept days, in the template's order: the athlete's
    preferred days when they name as many, else each day's template position,
    moved off a forced rest day (or another day) to the nearest free one.
    With days of different lengths (`minutes`), the days `is_long` says need
    time take the longest ones."""
    if preferred and len(preferred) >= len(kept):
        days = sorted(preferred)[:len(kept)]
    else:
        days, taken = [], set()
        positions = {p for p, _ in kept}
        for position, _ in kept:
            day = position
            if day in forced_rest or day in taken:
                free = [d for d in range(1, 8) if d not in forced_rest and d not in taken
                        and d not in positions - {position}] or \
                    [d for d in range(1, 8) if d not in forced_rest and d not in taken]
                if not free:
                    continue  # more days than the week allows: the last ones go
                day = min(free, key=lambda d: (abs(d - position), d))
            taken.add(day)
            days.append(day)
        days.sort()
    specs = [spec for _, spec in kept][:len(days)]
    if minutes and len({minutes.get(d) for d in days}) > 1:
        longs = [s for s in specs if is_long(s)]
        if longs:
            longest = sorted(sorted(days, key=lambda d: (-(minutes.get(d) or 0), d))[:len(longs)])
            others = [d for d in days if d not in longest]
            out = list(zip(longest, longs)) + list(zip(others, [s for s in specs if not is_long(s)]))
            return sorted(out, key=lambda x: x[0])
    return list(zip(days, specs))


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
    # A borrowed slot's role names where it came from (`source_slot` reads it
    # back), so a swap finds the slot in its own archetype.
    if warm:
        slots += _prefixed(warm, f"warm_up__{warm['id']}__", f"Warm-up ({warm['name']}). ")
    for k, (_, arch) in enumerate(pieces):
        slots += _prefixed(arch, '' if k == 0 else f"{arch['id']}__",
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
    cap = constraints.get('session_time_minutes', 60)
    day_configs = constraints.get('day_configs') or {}
    day_minutes = {d: min(cap, (day_configs.get(d) or {}).get('minutes', cap)) for d in range(1, 8)}
    placed = place_days(kept, sorted(constraints.get('preferred_days') or []),
                        sorted(constraints.get('forced_rest_days') or []), day_minutes,
                        lambda spec: categories.get(spec['categories'][0], {}).get('long_day', False))
    warm_cat = framework.get('warm_up_category')
    schedule: dict = {}

    def own(cat: str, minutes: float) -> dict | None:
        """The next workout of the category's own pool that fits, a fresh one
        (not picked in the last week) first."""
        spec = categories.get(cat)
        if spec is None:
            return None
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
                    return archetypes[aid]
        return None

    def fallback(cat: str, minutes: float) -> tuple[str, dict] | None:
        """The category's declared fallbacks, breadth first; the week says so once."""
        queue, seen = list((categories.get(cat) or {}).get('fallback') or []), {cat}
        while queue:
            other = queue.pop(0)
            if other in seen or other not in categories:
                continue
            seen.add(other)
            found = own(other, minutes)
            if found:
                notes.append(f"No {categories[cat]['name']} workout fits as written (equipment, injuries or "
                             f"{minutes:g} minutes); {categories[other]['name']} in its place.")
                return other, found
            queue += categories[other].get('fallback') or []
        return None

    for day, spec in placed:
        limit = day_minutes[day]
        warm_spec = categories.get(warm_cat) if warm_cat else None
        wants_warm = bool(warm_spec) and (spec['warm_up'] if spec['warm_up'] is not None else
                                          categories.get(spec['categories'][0], {}).get('warm_up', True))
        # The shortest warm-up this athlete can do is what the day keeps free.
        warm_min = min((archetypes[a].get('duration_estimate_minutes') or 0
                        for a in (warm_spec or {}).get('archetypes', [])
                        if a in archetypes and fits(archetypes[a], limit)), default=None)
        if warm_min is None:
            wants_warm = False
        pieces = []
        left = limit - (warm_min or 0 if wants_warm else 0)
        for cat in spec['categories']:
            name = categories.get(cat, {}).get('name', cat)
            arch = own(cat, left)
            found = (cat, arch) if arch is not None else None
            if found is None and wants_warm and not pieces:
                # The written workout before its warm-up: without room for
                # both, the athlete warms up on their own.
                arch = own(cat, limit)
                if arch is not None:
                    found, wants_warm, left = (cat, arch), False, limit
                    notes.append(f"{arch['name']} fills {limit:g} minutes; its day has no "
                                 'warm-up from the list — warm up on your own.')
            if found is None:
                found = fallback(cat, left)
            if found is None:
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
        if wants_warm:
            warm = own(warm_cat, limit - sum(a.get('duration_estimate_minutes') or 0 for _, a in pieces))
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


def prior_entries(phase_sequence: list, first_entry: dict) -> list[dict]:
    """The templated week entries a track ran before `first_entry`, from its
    first phase: what a regenerate replays to resume each pool's rotation."""
    from .phases import week_entry
    out, n = [], 1
    target = first_entry.get('phase_id')
    for ph in phase_sequence or []:
        last = ph.get('phase_id') == target
        weeks = (first_entry.get('week_in_phase', 1) - 1) if last else int(ph.get('weeks') or 1)
        for wip in range(1, weeks + 1):
            entry = week_entry(ph, wip, n)
            n += 1
            if entry.get('week_template'):
                out.append(entry)
        if last:
            break
    else:
        return []  # the first week's phase is not in this track
    return out


def regenerate_day(framework: dict, category: str | None, modality: str, constraints: dict,
                   archetypes: dict, fits, choose, exclude: set = frozenset()) -> dict | None:
    """One templated day picked afresh (a single-session regenerate): another
    workout of the day's category the athlete can do as written — the
    category the client names, else the first whose modality matches — opened
    by a warm-up that fits beside it. `choose` picks among the candidates (the
    route passes random.choice, so a regenerate gives something new)."""
    categories = framework.get('categories') or {}
    warm_cat = framework.get('warm_up_category')
    if category not in categories:
        category = next((c for c, spec in categories.items()
                         if c != warm_cat and spec['modality'] == modality), None)
    if category is None:
        return None
    spec = categories[category]
    limit = constraints.get('session_time_minutes', 60)
    pool = [archetypes[a] for a in spec['archetypes'] if a in archetypes and a not in exclude]
    found = [a for a in pool if fits(a, limit)] or \
        [archetypes[a] for a in spec['archetypes'] if a in archetypes and fits(archetypes[a], limit)]
    if not found:
        return None
    main = choose(found)
    warm = None
    if spec.get('warm_up', True) and warm_cat in categories:
        left = limit - (main.get('duration_estimate_minutes') or 0)
        warms = [archetypes[a] for a in categories[warm_cat]['archetypes'] if a in archetypes and fits(archetypes[a], left)]
        warm = choose(warms) if warms else None
    return {'modality': spec['modality'], 'category': category, 'category_name': spec['name'],
            'pieces': [{'category': category, 'archetype_id': main['id'], 'name': main['name']}],
            **({'warm_up': {'archetype_id': warm['id'], 'name': warm['name']}} if warm else {}),
            '_forced_archetype': compose([(category, main)], warm, False, categories)}


def source_slot(archetype_id: str, role: str) -> tuple[str, str]:
    """(archetype id, role) of a composed session's slot: a warm-up's
    `warm_up__<id>__<role>`, a second piece's `<id>__<role>`, else as given."""
    parts = role.split('__')
    if len(parts) == 3 and parts[0] == 'warm_up':
        return parts[1], parts[2]
    if len(parts) == 2:
        return parts[0], parts[1]
    return archetype_id, role
