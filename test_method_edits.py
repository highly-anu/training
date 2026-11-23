#!/usr/bin/env python
"""Renaming an athlete's own method and editing its words (src/method_edits.py,
package_store.edit_text, PATCH /api/methods/<id>): names, summaries and notes
are written without a model or a build; ids, numbers and structure are
refused; the program built from the method takes the new names.

Run: SUPABASE_URL='' .venv/bin/python test_method_edits.py
"""
from __future__ import annotations

import glob
import os
import sys

import test_private_packages as fixture   # sets the environment and a store of its own

import yaml  # noqa: E402

from src import loader, method_edits, package_store  # noqa: E402

FAILURES: list[str] = []
ANN, BEN = 'user-ann', 'user-ben'


def check(label: str, condition: bool, detail='') -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        FAILURES.append(label)


def shape(files: dict) -> tuple[str, str, str, str, str]:
    """(track id, phase id, an archetype id, its file, one of its roles)."""
    phil = yaml.safe_load(files['philosophy.yaml'])
    track = phil['tracks'][0]
    path = sorted(p for p in files if p.startswith('archetypes/'))[0]
    arch = yaml.safe_load(files[path])
    return track['id'], track['phases'][0]['id'], arch['id'], path, arch['slots'][0]['role']


def test_apply():
    print('the edits, on a file map')
    pkg, files = fixture.package_for(ANN)
    track, phase, session, path, role = shape(files)
    out, problems, changed = method_edits.apply(files, {
        'name': '  Stone   days ', 'summary': 'Lift odd things.',
        'tracks': {track: {'name': 'The long road', 'phases': {phase: {'name': 'Opening weeks', 'focus': 'Volume'}}}},
        'sessions': {session: {'name': 'Heavy day', 'notes': 'Go slow.', 'slots': {role: {'notes': 'Brace first.'}}}}})
    phil, arch = yaml.safe_load(out['philosophy.yaml']), yaml.safe_load(out[path])
    check('no problem, two files changed', problems == [] and changed == ['philosophy.yaml', path], (problems, changed))
    check('the name is written, its spaces tidied', phil['name'] == 'Stone days' and phil['notes'] == 'Lift odd things.')
    check("a track's and a phase's words", phil['tracks'][0]['name'] == 'The long road'
          and phil['tracks'][0]['phases'][0]['name'] == 'Opening weeks' and phil['tracks'][0]['phases'][0]['focus'] == 'Volume')
    check("a session's name and notes, a movement's note", arch['name'] == 'Heavy day' and arch['notes'] == 'Go slow.'
          and arch['slots'][0]['notes'] == 'Brace first.')
    before, after = yaml.safe_load(files['philosophy.yaml']), phil
    check('nothing else moved: the id, the tracks and phases by id, the key order',
          after['id'] == before['id'] == pkg and list(after) == list(before)
          and [t['id'] for t in after['tracks']] == [t['id'] for t in before['tracks']])
    was, now = yaml.safe_load(files[path]), arch
    for doc in (was, now):
        doc.pop('name', None), doc.pop('notes', None)
        for s in doc['slots']:
            s.pop('notes', None)
    check("a session's slots are otherwise what they were", was == now)
    check('the input is untouched', files['philosophy.yaml'] != out['philosophy.yaml']
          and yaml.safe_load(files['philosophy.yaml'])['name'] != 'Stone days')
    check('other files are the same objects', all(out[p] is files[p] for p in files if p not in changed))
    same, problems, changed = method_edits.apply(files, {'name': yaml.safe_load(files['philosophy.yaml'])['name']})
    check('an edit that changes nothing changes no file', problems == [] and changed == [] and same == files)
    cleared, problems, _ = method_edits.apply(out, {'sessions': {session: {'notes': '  '}}})
    check('an empty note removes the key', problems == [] and 'notes' not in yaml.safe_load(cleared[path]))

    print('what an edit may not do')
    for label, edits, code in [
        ('an id', {'id': 'other'}, 'not_editable'),
        ("a slot's numbers", {'sessions': {session: {'slots': {role: {'sets': 9}}}}}, 'not_editable'),
        ("a session's minutes", {'sessions': {session: {'duration_estimate_minutes': 5}}}, 'not_editable'),
        ("a phase's weeks", {'tracks': {track: {'phases': {phase: {'weeks': 99}}}}}, 'not_editable'),
        ('an empty name', {'name': '   '}, 'bad_name'),
        ('a name past 80 characters', {'name': 'x' * 81}, 'bad_name'),
        ('a number for a name', {'name': 7}, 'not_text'),
        ('a note past 2000 characters', {'summary': 'x' * 2001}, 'too_long'),
        ('a track the method lacks', {'tracks': {'nope': {'name': 'A'}}}, 'unknown'),
        ('a session the method lacks', {'sessions': {'nope': {'name': 'A'}}}, 'unknown'),
        ('a slot the session lacks', {'sessions': {session: {'slots': {'nope': {'notes': 'A'}}}}}, 'unknown'),
        ('nothing at all', {}, 'bad_edit'),
        ('a list', ['name'], 'bad_edit'),
    ]:
        got, problems, changed = method_edits.apply(files, edits)
        check(f'{label} is refused ({code})', [p['code'] for p in problems] == [code] and got is files and changed == [],
              problems)
    _, problems, _ = method_edits.apply(files, {'name': 'Fine', 'sessions': {session: {'slots': {role: {'reps': 3}}}}})
    check('one refused edit refuses them all', len(problems) == 1)


def test_store():
    print('through the store')
    pkg, files = fixture.package_for(ANN)
    track, phase, session, path, role = shape(files)
    check('installed', package_store.install(ANN, files)['installed'])
    check('no such method: None', package_store.edit_text(ANN, 'zz_none', {'name': 'A'}) is None
          and package_store.edit_text(BEN, pkg, {'name': 'Theirs now'}) is None)
    done = package_store.edit_text(ANN, pkg, {'name': 'Stone days', 'sessions': {session: {'notes': 'Go slow.'}}})
    check('a rename is the next revision of the same method', done['ok'] and done['revision'] == 2
          and done['name'] == 'Stone days' and sorted(done['changed']) == sorted(['philosophy.yaml', path]), done)
    listed = package_store.list_packages(ANN)
    check('the list says the new name', [(p['id'], p['name'], p['revision']) for p in listed] == [(pkg, 'Stone days', 2)])
    with loader.overlay(package_store.overlay_for(ANN)):
        names = {p['id']: p['name'] for p in loader.load_philosophies()}
        check('it loads under the new name', names.get(pkg) == 'Stone days', names.get(pkg))
        check('and still generates', fixture.generates(pkg) > 0)
    again = package_store.edit_text(ANN, pkg, {'name': 'Stone days'})
    check('the same name again writes nothing', again['ok'] and again['changed'] == [] and again['revision'] == 2)
    refused = package_store.edit_text(ANN, pkg, {'sessions': {session: {'slots': {role: {'sets': 9}}}}})
    check('a refused edit stores nothing', not refused['ok'] and refused['problems']
          and package_store.list_packages(ANN)[0]['revision'] == 2)

    print('a method an engine change set aside can still be renamed')
    mine = package_store.overlay_for(ANN)
    fw = next(p for p in glob.glob(os.path.join(mine, pkg, 'frameworks', '*.yaml')))
    stored = package_store.get_package(ANN, pkg)['files']
    key = 'frameworks/' + os.path.basename(fw)
    broken = {**stored, key: stored[key] + '\nno_such_key_in_the_schema: true\n'}
    package_store._rewrite(ANN, pkg, broken, 'Stone days')       # what an older engine once accepted
    package_store.forget(ANN)
    check('it no longer passes the gate', not package_store.check(ANN, broken, smoke=False)['ok'])
    late = package_store.edit_text(ANN, pkg, {'name': 'Stones, set aside'})
    check('renamed all the same: the edit brought no problem', late['ok'] and late['name'] == 'Stones, set aside', late)
    package_store.remove(ANN, pkg)


def test_program_names():
    print("the program's copies of the names")
    pkg, files = fixture.package_for(ANN)
    track, phase, session, path, role = shape(files)
    phil = yaml.safe_load(files['philosophy.yaml'])
    program = {'sourceGoalIds': [pkg], 'currentProgram': {
        'goal': {'id': f'_phil_{pkg}', 'name': phil['name'],
                 'track': {'id': track, 'name': 'Old track', 'philosophy_id': pkg},
                 'phase_sequence': [{'id': phase, 'name': 'Old phase', 'weeks': 4}]},
        'weeks': [{'week_number': 1, 'track_id': track, 'phase_id': phase, 'phase_name': 'Old phase', 'schedule': {}},
                  {'week_number': 2, 'track_id': 'another', 'phase_id': phase, 'phase_name': 'Old phase', 'schedule': {}}]}}
    edited, _, _ = method_edits.apply(files, {'name': 'Stone days', 'tracks': {track: {
        'name': 'The long road', 'phases': {phase: {'name': 'Opening weeks'}}}}})
    out = method_edits.rename_in_program(program, pkg, edited)
    goal, weeks = out['currentProgram']['goal'], out['currentProgram']['weeks']
    check('the goal, its track and its phases take the new names', goal['name'] == 'Stone days'
          and goal['track']['name'] == 'The long road' and goal['phase_sequence'][0]['name'] == 'Opening weeks', goal)
    check("each of the track's weeks too, and no other track's", [w['phase_name'] for w in weeks] == ['Opening weeks', 'Old phase'])
    check('nothing else of the program moved', {**out['currentProgram'], 'goal': None, 'weeks': None}
          == {**program['currentProgram'], 'goal': None, 'weeks': None}
          and goal['phase_sequence'][0]['weeks'] == 4 and weeks[0]['schedule'] == {})
    check('the stored program is not mutated', program['currentProgram']['goal']['name'] == phil['name'])
    check('a program that is up to date is left alone', method_edits.rename_in_program(out, pkg, edited) is None)
    other = {'currentProgram': {'goal': {'id': '_phil_crossfit', 'name': 'CrossFit',
                                         'track': {'id': track, 'philosophy_id': 'crossfit'}}, 'weeks': []}}
    check("another method's program is left alone", method_edits.rename_in_program(other, pkg, edited) is None
          and method_edits.rename_in_program({}, pkg, edited) is None)


def test_route():
    print('PATCH /api/methods/<id> (local dev: every request is local-dev-user)')
    import api
    from src import db
    client = api.app.test_client()
    me = 'local-dev-user'
    pkg, files = fixture.package_for(me)
    track, phase, session, path, role = shape(files)
    check('installed', client.post('/api/packages', json={'files': files}).status_code == 200)
    check('an unknown method is 404', client.patch('/api/methods/zz_none', json={'name': 'A'}).status_code == 404)
    bad = client.patch(f'/api/methods/{pkg}', json={'sessions': {session: {'slots': {role: {'sets': 9}}}}})
    check('numbers are refused, 422 with the problems', bad.status_code == 422
          and bad.get_json()['problems'][0]['code'] == 'not_editable', bad.get_json())
    check('and no body at all', client.patch(f'/api/methods/{pkg}').status_code == 422)

    phil = yaml.safe_load(files['philosophy.yaml'])
    program = {'sourceGoalIds': [pkg], 'currentProgram': {
        'goal': {'id': f'_phil_{pkg}', 'name': phil['name'], 'track': {'id': track, 'philosophy_id': pkg}}, 'weeks': []}}
    saved = []
    real_get, real_save = db.get_user_program, db.save_user_program
    db.get_user_program = lambda user_id: saved[-1] if saved else program
    db.save_user_program = lambda user_id, data: saved.append(data)
    try:
        done = client.patch(f'/api/methods/{pkg}', json={'name': 'Stone days'})
        body = done.get_json()
        check('a rename answers the name and the revision', done.status_code == 200 and body['name'] == 'Stone days'
              and body['revision'] == 2 and body['changed'] == ['philosophy.yaml'], body)
        check('the program built from it is saved with the new name', body['programRenamed'] is True
              and len(saved) == 1 and saved[0]['currentProgram']['goal']['name'] == 'Stone days')
        quiet = client.patch(f'/api/methods/{pkg}', json={'sessions': {session: {'notes': 'Go slow.'}}}).get_json()
        check('an edit of a note leaves the program alone', quiet['programRenamed'] is False and len(saved) == 1, quiet)
    finally:
        db.get_user_program, db.save_user_program = real_get, real_save
    methods = client.get('/api/methods').get_json()['methods']
    check('GET /api/methods says the new name', [(m['id'], m['name']) for m in methods] == [(pkg, 'Stone days')], methods)
    listed = {p['id']: p for p in client.get('/api/philosophies').get_json()}
    check('and so does /api/philosophies, at once', listed[pkg]['name'] == 'Stone days' and listed[pkg].get('own') is True)
    doc = client.get(f'/api/philosophies/{pkg}/describe').get_json()
    check("the describe page has the session's note", doc['name'] == 'Stone days'
          and doc['sessions'][session]['note'] == 'Go slow.')

    os.environ['PACKAGE_BUILDER'] = 'off'
    try:
        check("behind the builder's gate: off, 403", client.patch(f'/api/methods/{pkg}', json={'name': 'B'}).status_code == 403)
    finally:
        os.environ.pop('PACKAGE_BUILDER', None)
    check('removed', client.delete(f'/api/methods/{pkg}').status_code == 200)


def main() -> int:
    test_apply()
    test_store()
    test_program_names()
    test_route()
    if FAILURES:
        print(f'{len(FAILURES)} failed: {FAILURES}')
        return 1
    print('all passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
