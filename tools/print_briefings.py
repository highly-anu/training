"""Each package's briefing beside its own programs, for reading.

    SUPABASE_URL='' .venv/bin/python tools/print_briefings.py [package id …]

Generates every track (a level and a number of days it accepts), marks the
first week done as written — a contract session confirmed clean with every
lift made, anything else logged by its slot type — and prints the second
week's briefings compactly: the entry that read each item, today's line, how
many earlier occurrences, the last one, the cycle and the suggestion. What a
package's default reads poorly here is what its briefing.yaml is for
(docs/roadmap.md 22.4).
"""
import os
import sys
from datetime import date, timedelta
os.environ['DATABASE_URL'] = ''
os.environ['SUPABASE_URL'] = ''
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import api
from src import briefing, briefing_spec, loader, training_contract
EQ = [e['id'] for e in loader.load_equipment()]
DAYS = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday']
START = date(2026, 11, 2)
c = api.app.test_client()
only = sys.argv[1:]
for phil in loader.load_philosophies():
    pid = phil['id']
    if only and pid not in only: continue
    for track in phil.get('tracks') or []:
        levels = track.get('training_levels') or ['intermediate']
        level = 'intermediate' if 'intermediate' in levels else levels[0]
        g = {}
        for level in ([level] + [l for l in ('novice', 'intermediate', 'advanced') if l != level]):
            for days in (5, 6, 7, 4, 3):
                r = c.post('/api/programs/generate', json={'philosophy_id': pid, 'track_id': track['id'], 'num_weeks': 3, 'persist': False,
                    'constraints': {'training_level': level, 'days_per_week': days, 'session_time_minutes': 90, 'equipment': EQ, 'injury_flags': []}})
                g = r.get_json() or {}
                if g.get('weeks'): break
            if g.get('weeks'): break
        if not g.get('weeks'):
            print(f"=== {pid}/{track['id']} ({level}): no program: {[e.get('code') for e in (g.get('validation') or {}).get('errors') or []]}"); continue
        rows = []
        for wi, w in enumerate(g['weeks']):
            for d in DAYS:
                for i, s in enumerate(w['schedule'].get(d) or []):
                    rows.append({'date': str(START + timedelta(days=wi*7+DAYS.index(d))), 'key': f"{w['week_number']}-{d}-{i}", 'session': s, 'current': True, 'wi': wi})
        hist = []
        for row in rows:
            if row['wi'] > 0: continue
            s = row['session']
            ex = {}
            if s.get('modules'):
                try: ex = training_contract.confirmation_outcomes(s, True, 6, None, {eid: {'made': True, 'weightKg': 60} for m in s['modules'] for eid in (m.get('lifts') or {})})
                except Exception as e: ex = {}
            else:
                for ea in s.get('exercises') or []:
                    eid = (ea.get('exercise') or {}).get('id'); st = ea.get('slot_type'); load = ea.get('load') or {}
                    if not eid: continue
                    if st == 'sets_reps': ex[eid] = {'sets': [{'setIndex': k, 'repsActual': load.get('reps') if isinstance(load.get('reps'), int) else 5, 'weightKg': load.get('weight_kg') or 40, 'completed': True} for k in range(int(load.get('sets') or 1))]}
                    elif st in ('amrap', 'emom'): ex[eid] = {'rounds': 7}
                    elif st in ('for_time', 'rounds_for_time'): ex[eid] = {'durationSec': 754}
                    elif st in ('time_domain', 'skill_practice'): ex[eid] = {'durationSec': 60 * int(load.get('duration_minutes') or 20)}
                    elif st == 'distance': ex[eid] = {'distanceKm': 5.2, 'durationSec': 1900}
                    elif st == 'static_hold': ex[eid] = {'sets': [{'setIndex': 0, 'durationSeconds': 40, 'completed': True}]}
            hist.append(dict(row, log={'completedAt': row['date'] + 'T07:00:00Z', 'exercises': ex}))
        track_mods = {}
        print(f"\n=== {pid}/{track['id']} ({level}) spec={briefing_spec.spec_for(pid)['source']}")
        shown = 0
        for row in rows:
            if row['wi'] != 1 or shown >= 4: continue
            s = row['session']
            mods = training_contract.modules_for(pid, [m.get('id') for m in s.get('modules') or []], track['id'])
            doc = briefing.build(s, date=row['date'], key=row['key'], history=hist,
                                 modules={k: {'name': m.get('name'), 'progression': m.get('progression')} for k, m in mods.items()})
            shown += 1
            print(f"  -- {row['key']} {(s.get('archetype') or {}).get('name')} [{len(s.get('exercises') or [])} ex → {len(doc['items'])} items]")
            for it in doc['items'][:7]:
                last = it['last']['text'][:60] if it['last'] else '-'
                print(f"     {it['entry'][8:] if it['entry'].startswith('default_') else it['entry']:9} {it['title'][:34]:34} | {it['today']['text'][:44]:44} | n={it['times']} run={'/'.join(str(len(e['run'])) + ((e.get('metric') or {}).get('id', '-')[:6]) for e in it['exercises'])} last={last} | {(it.get('cycle') or {}).get('text','')} | {(it.get('suggestion') or {}).get('text','-')[:90]}")
            if len(doc['items']) > 7: print(f"     … {len(doc['items'])-7} more items")
