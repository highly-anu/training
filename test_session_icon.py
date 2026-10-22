#!/usr/bin/env python
"""src/session_icon.py: each session's workout icon, derived on read.

Run: SUPABASE_URL='' .venv/bin/python test_session_icon.py
"""
from __future__ import annotations

import json
import os
import sys

from src import session_icon

FAILURES: list[str] = []


def check(label: str, condition: bool, detail: str = '') -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        FAILURES.append(label)


def ea(eid, role, slot_type='emom', **extra):
    return {'exercise': {'id': eid}, 'slot_role': role, 'slot_type': slot_type, **extra}


def test_vocabulary() -> None:
    print('the vocabulary')
    ids = session_icon.icon_ids()
    check('lists the kettlebell', 'kettlebell' in ids, str(ids))
    vocab = session_icon.vocabulary()
    check('every fallback is an icon', all(i['fallback'] in ids for i in vocab['icons'] if i['fallback']))
    check('every category default is an icon',
          set(vocab['exercise_category_defaults'].values()) | set(vocab['archetype_category_defaults'].values()) <= ids)


def test_resolution() -> None:
    print('resolution: the main exercise decides')
    # A contract day of two modules is led by the first module's first exercise.
    day = {'modality': 'power', 'archetype': {'id': 'kb_ballistic_session'},
           'modules': [{'id': 'swing', 'archetype_id': 'kb_ballistic_session',
                        'exercise_ids': ['wk_kb_swing_two_hand']},
                       {'id': 'deck_squat', 'archetype_id': 'kb_squat_practice',
                        'exercise_ids': ['wk_deck_squat']}],
           'exercises': [ea('kb_deadlift', 'swing_prep'), ea('wk_kb_swing_two_hand', 'swing_main'),
                         ea('wk_kb_halo', 'swing_recovery'), ea('wk_deck_squat', 'deck_squat_squat')]}
    check('Swing + Deck Squat → kettlebell', session_icon.session_icon(day) == 'kettlebell')
    # No modules: the first slot that is not preparation.
    after_warmup = {'modality': 'strength_endurance', 'archetype': {'id': 'not_an_archetype'},
                    'exercises': [ea('back_squat', 'warm_up'), ea('wk_kb_snatch', 'main')]}
    check('lead exercise past the warm-up', session_icon.session_icon(after_warmup) == 'kettlebell',
          str(session_icon.session_icon(after_warmup)))
    camel = {'modality': 'power', 'archetype': {'id': 'not_an_archetype'},
             'exercises': [{'exercise': {'id': 'back_squat'}, 'slotRole': 'prep'},
                           {'exercise': {'id': 'wk_kb_squat_goblet'}, 'slotRole': 'main'}]}
    check('camelCase rows (iOS saves)', session_icon.session_icon(camel) == 'kettlebell')
    # A kettlebell warm-up before a barbell lift is not a kettlebell session,
    # whatever the archetype's category.
    barbell = {'modality': 'max_strength', 'archetype': {'id': 'not_an_archetype', 'category': 'kettlebell'},
               'exercises': [ea('wk_kb_halo', 'warm_up'), ea('back_squat', 'main', 'sets_reps')]}
    check('barbell main lift → no icon', session_icon.session_icon(barbell) is None,
          str(session_icon.session_icon(barbell)))
    # No exercise to read: the archetype's category.
    empty = {'modality': 'power', 'archetype': {'id': 'not_an_archetype', 'category': 'kettlebell'},
             'exercises': []}
    check('no exercises → archetype category', session_icon.session_icon(empty) == 'kettlebell')
    plain = {'modality': 'aerobic_base', 'archetype': {'id': 'not_an_archetype', 'category': 'conditioning'},
             'exercises': []}
    check('none → the client draws the modality', session_icon.session_icon(plain) is None)
    check('archetype id alone (history rows)',
          session_icon.for_archetype('kb_snatch_practice') == 'kettlebell'
          and session_icon.for_archetype(None) is None)


def test_with_icons_and_strip() -> None:
    print('derived, then stripped')
    weeks = [{'week_number': 1, 'schedule': {'Monday': [
        {'modality': 'power', 'archetype': {'id': 'kb_snatch_practice'}, 'icon': 'stale', 'exercises': []}],
        'Tuesday': []}}]
    out = session_icon.with_icons(weeks)
    check('with_icons replaces a stale icon', out[0]['schedule']['Monday'][0]['icon'] == 'kettlebell')
    check('with_icons leaves its input alone', weeks[0]['schedule']['Monday'][0]['icon'] == 'stale')
    stripped = session_icon.strip({'weeks': out})
    check('strip removes every icon', 'icon' not in stripped['weeks'][0]['schedule']['Monday'][0])
    cp = {'weeks': [{'schedule': {'Monday': [{'modality': 'power'}]}}]}
    check('strip returns the same object when there is none', session_icon.strip(cp) is cp)
    from src import program_history
    a = {'currentProgram': {'weeks': out}}
    b = {'currentProgram': {'weeks': session_icon.strip({'weeks': out})['weeks']}}
    check('content hash ignores icons', program_history.content_hash(a) == program_history.content_hash(b))


GP_BODY = {'philosophy_id': 'wildman_kettlebell', 'num_weeks': 2,
           'constraints': {'days_per_week': 4, 'session_time_minutes': 60, 'training_level': 'intermediate',
                           'equipment': ['kettlebell', 'open_space'], 'injury_flags': []}}


def _icons(program: dict) -> list[tuple[str, str | None]]:
    return [((s.get('archetype') or {}).get('id'), s.get('icon'))
            for w in program.get('weeks') or [] for ss in (w.get('schedule') or {}).values() for s in ss]


def test_api() -> None:
    print('the API serves it and never stores it')
    os.environ.setdefault('SUPABASE_URL', '')
    import api
    from src import db
    client = api.app.test_client()
    resp = client.post('/api/programs/generate', json=GP_BODY)
    data = resp.get_json() or {}
    icons = _icons(data)
    check('General Practice generates', resp.status_code == 200 and icons, f"{resp.status_code}")
    check('every General Practice session is a kettlebell session',
          icons and {i for _, i in icons} == {'kettlebell'}, str(set(icons)))
    check('in both its modalities', {s.get('modality') for w in data['weeks']
                                     for ss in w['schedule'].values() for s in ss} == {'power', 'movement_skill'})
    novice = client.post('/api/programs/generate', json={
        **GP_BODY, 'constraints': {**GP_BODY['constraints'], 'training_level': 'novice'}}).get_json() or {}
    check('a novice technique day too',
          ('kb_movement_skill_session', 'kettlebell') in _icons(novice), str(set(_icons(novice))))
    barbell = client.post('/api/programs/generate', json={
        'philosophy_id': 'starting_strength', 'num_weeks': 1,
        'constraints': {'days_per_week': 3, 'session_time_minutes': 75, 'training_level': 'novice',
                        'equipment': ['barbell', 'rack', 'plates', 'bench'], 'injury_flags': []}}).get_json() or {}
    check('a barbell program has none', _icons(barbell) and not any(i for _, i in _icons(barbell)),
          str(_icons(barbell)[:3]))

    stored: dict = {}
    real = {k: getattr(db, k) for k in ('_get_pg_conn',)}
    try:
        db._get_pg_conn = lambda: None
        db._ensure_local_storage()
        db.save_user_program('session-icon-test', {'currentProgram': data})
        path = db._local_storage_dir / 'session-icon-test_program.json'
        stored = json.loads(path.read_text())
        check('save strips every icon', not any(i for _, i in _icons(stored['currentProgram'])))
        # GET derives them again from a program stored without any.
        saved_get = db.get_user_program
        db.get_user_program = lambda uid: json.loads(path.read_text())
        try:
            got =client.get('/api/user/program').get_json() or {}
        finally:
            db.get_user_program = saved_get
        check('GET derives them on read', _icons(got.get('currentProgram') or {}) == icons,
              str(_icons(got.get('currentProgram') or {})[:4]))
        path.unlink()
    finally:
        for k, v in real.items():
            setattr(db, k, v)

    # The watch's session carries it too.
    first = next(s for w in data['weeks'] for ss in w['schedule'].values() for s in ss)
    enc = api.encode_watch_session(first, '1-Monday-0', spec_level=1)
    check('today-session carries the icon', enc.get('icon') == first['icon'], str(enc.get('icon')))


def main() -> int:
    test_vocabulary()
    test_resolution()
    test_with_icons_and_strip()
    test_api()
    print()
    if FAILURES:
        print(f"{len(FAILURES)} failure(s)")
        return 1
    print('all session icon tests passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
