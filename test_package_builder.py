#!/usr/bin/env python
"""The model loop that writes an athlete's method (docs/roadmap.md 21.3):
src/package_builder.py.

No model is called: `package_builder.MODEL_TURN` — the one place a request
leaves the process — is a script here, answering each request with the turn a
case needs (tool calls, a pause, a refusal, a cut-off). Everything else is
real: the tools, the gates on the draft (the from-scratch test package,
test_packages/scratch_minimal), the worker, the store, the install and the
routes.

Run: SUPABASE_URL='' .venv/bin/python test_package_builder.py   (--write re-records the web's fixture)
"""
from __future__ import annotations

import atexit
import copy
import itertools
import json
import os
import shutil
import sys
import tempfile

os.environ['SUPABASE_URL'] = ''
os.environ['DATABASE_URL'] = ''
os.environ.pop('TRAINING_PACKAGES_DIR', None)
os.environ.pop('PACKAGE_BUILDER', None)
os.environ.pop('PACKAGE_BUILDER_EFFORT', None)
os.environ.pop('PACKAGE_BUILDER_MODEL', None)
os.environ['PACKAGE_BUILDER_DAILY_LIMIT'] = '1000'
os.environ['ANTHROPIC_API_KEY'] = 'test-key'      # the builder reports itself available; nothing calls a model here
BASE = tempfile.mkdtemp(prefix='package-builder-')
atexit.register(shutil.rmtree, BASE, True)

import test_private_packages as tpp  # noqa: E402  (sets TRAINING_USER_PACKAGES_DIR to its own scratch folder)

import api  # noqa: E402
from src import build_store, build_worker, package_builder, package_store  # noqa: E402

FAILURES: list[str] = []
ME = 'local-dev-user'
client = api.app.test_client()
DESCRIPTION = 'Lift an atlas stone to the shoulder twice a week and walk easily twice a week, eight weeks.'
ANSWERS = {'days': 4, 'minutes': 45, 'level': 'intermediate'}
PKG, FILES = tpp.package_for(ME, 'stones', tpp.SCRATCH)
_ids = itertools.count(1)


def check(label: str, condition: bool, detail='') -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {str(detail)[:600]}")
        FAILURES.append(label)


# ── A scripted model ─────────────────────────────────────────────────────────

def use(name, **args):
    return {'type': 'tool_use', 'id': f'toolu_{next(_ids)}', 'name': name, 'input': args}


def text(words):
    return {'type': 'text', 'text': words}


def say(*blocks, stop='tool_use', out=100, **usage):
    return {'content': list(blocks), 'stop_reason': stop, 'model': 'scripted',
            'usage': {'input_tokens': 10, 'output_tokens': out, 'cache_read_input_tokens': 1000, **usage}}


def write_all(files=None, **usage):
    return say(*[use('write_file', path=p, content=c) for p, c in sorted((files or FILES).items())], **usage)


class Crash(BaseException):
    """The process dying under a build (not an Exception: nothing catches it)."""


class Script:
    """Answers each model request with the next scripted turn and keeps what
    was asked. A step may be a message, a callable (params → message) or an
    exception to raise."""

    def __init__(self, *steps):
        self.steps = list(steps)
        self.requests: list[dict] = []

    def __call__(self, params, alive):
        self.requests.append(copy.deepcopy(params))
        alive()
        if not self.steps:
            raise AssertionError('the script ran out: the loop asked for a turn nobody expected')
        step = self.steps.pop(0)
        if isinstance(step, BaseException):
            raise step
        return step(params) if callable(step) else step


def results_of(request: dict) -> list[dict]:
    """The tool results the loop sent back in a request's last message."""
    last = request['messages'][-1]
    return [b for b in last['content'] if b.get('type') == 'tool_result'] if last['role'] == 'user' else []


def clean():
    for p in package_store.list_packages(ME):
        package_store.remove(ME, p['id'])


def run(script: Script, request=None, draft=None, limits=None) -> dict:
    """One build from a fresh row to its end through the worker."""
    request = request or {'description': DESCRIPTION, 'answers': ANSWERS, 'pastedText': '', 'webSearch': False}
    row = build_store.create(ME, request, draft)
    return resume(script, build_store.claim_next(), limits)


def resume(script: Script, row: dict, limits=None) -> dict:
    saved = dict(package_builder.LIMITS)
    package_builder.LIMITS.update(limits or {})
    package_builder.MODEL_TURN = script
    build_worker.BUILDER = package_builder.build
    try:
        build_worker.run_build(row)
    finally:
        package_builder.LIMITS.clear()
        package_builder.LIMITS.update(saved)
        package_builder.MODEL_TURN = None
    return build_store.get(None, row['id'])


# ── Cases ────────────────────────────────────────────────────────────────────

def test_built():
    print('a method written, checked and installed')
    clean()
    script = Script(write_all(), say(use('check_package')), say(use('finish', summary=' Two stone days, two walks. ')))
    row = run(script)
    check('the build is done', row['status'] == 'done', row.get('error'))
    result = row.get('result') or {}
    check('with the package, its revision, the philosophy\'s name and the summary',
          result.get('packageId') == PKG and result.get('revision') == 1 and result.get('summary') == 'Two stone days, two walks.'
          and result.get('name') == package_store._name(FILES), result)
    check('installed as the draft was written', (package_store.get_package(ME, PKG) or {}).get('files') == FILES)

    first = script.requests[0]
    system = first['system'][0]
    check('the system prompt is the instructions, the spec and the core schemas, marked for caching',
          system['cache_control'] == {'type': 'ephemeral'} and 'How to write a package' in system['text']
          and all(f'# {k}.schema.json' in system['text'] for k in package_builder.CORE_SCHEMAS)
          and system['text'].startswith(package_builder.INSTRUCTIONS[:40]))
    check('and the same bytes on every request', all(r['system'] == first['system'] for r in script.requests))
    check('the request asks Opus 5.5 with adaptive thinking, an explicit effort and the server-side fallback',
          first['model'] == 'claude-opus-5-5' and first['thinking'] == {'type': 'adaptive'}
          and first['output_config'] == {'effort': 'high'} and first['fallbacks'] == 'default'
          and first['betas'] == ['server-side-fallback-2026-07-01'] and 'tool_choice' not in first
          and first['cache_control'] == {'type': 'ephemeral'})
    names = [t['name'] for t in first['tools']]
    check('with the eight tools, each streamed eagerly and closed to other fields, and no web tool',
          names == ['write_file', 'read_file', 'delete_file', 'list_files', 'get_schema', 'check_package', 'finish', 'decline']
          and all(t['eager_input_streaming'] is True and t['input_schema']['additionalProperties'] is False
                  for t in first['tools']), names)
    opening = first['messages'][0]['content'][0]['text']
    check('the first message is the athlete\'s request: their words, their answers, their prefix',
          len(first['messages']) == 1 and DESCRIPTION in opening and package_store.owner_prefix(ME) in opening
          and '4 days a week' in opening and '45 minutes' in opening and 'intermediate' in opening
          and 'not available' in opening, opening)
    check('history only grows: each request starts with the one before',
          all(b['messages'][:len(a['messages'])] == a['messages'] for a, b in zip(script.requests, script.requests[1:])))
    wrote = results_of(script.requests[1])
    check('every tool call of a turn is answered in one user message',
          len(wrote) == len(FILES) and not any(r.get('is_error') for r in wrote))
    answer = json.loads(results_of(script.requests[2])[0]['content'])
    check('check_package answers with the gate\'s result and the checks left',
          answer['ok'] is True and answer['problems'] == [] and answer['checks_left'] == package_builder.LIMITS['checks'] - 1,
          answer)
    week = answer.get('for_this_athlete') or {}
    check('and a week generated as the athlete who asked',
          week.get('feasible') is True and week.get('as', {}).get('days_per_week') == 4
          and week['as']['session_time_minutes'] == 45 and week['as']['equipment'] == 'everything'
          and len(week.get('week') or []) == 4, week)
    check('whole: every week of the track in lines, and a word on the equipment nobody listed',
          week.get('weeks', {}).get('shown') == week['weeks']['of'] > 1 and week['program'].startswith('Week 1 · ')
          and f"Week {week['weeks']['shown']} · " in week['program'] and '  Mon  ' in week['program']
          and 'every implement' in week['as'].get('note', ''), {k: v for k, v in week.items() if k != 'week'})
    usage = row['usage']
    check('the usage is recorded on the build', usage['turns'] == 3 and usage['checks'] == 1
          and usage['output_tokens'] == 300 and usage['cache_read_input_tokens'] == 3000 and usage['model'] == 'scripted',
          usage)
    check('finish on a draft that just passed pays for no second check', usage['checks'] == 1)
    public = build_store.public(row)
    check('the athlete sees stage and counts, never the transcript',
          public['progress']['stage'] == 'done' and public['progress']['turns'] == 3 and 'transcript' not in public
          and 'usage' not in public, public)


def test_fix_and_retry():
    print('real gate problems, fixed and checked again')
    clean()
    broken = dict(FILES)
    broken['exercises.yaml'] = 'exercises: []\n'
    script = Script(write_all(broken), say(use('check_package')),
                    say(use('write_file', path='exercises.yaml', content=FILES['exercises.yaml'])),
                    say(use('finish', summary='Done.')))
    row = run(script)
    check('(the gate alone would let it in, with warnings)', package_store.check(ME, broken)['ok']
          and package_store.check(ME, broken)['warnings'])
    answer = json.loads(results_of(script.requests[2])[0]['content'])
    check('a week with empty slots passes the gate but not the builder: each is a problem, as data',
          answer['ok'] is False and answer['problems']
          and all(set(p) == {'stage', 'code', 'file', 'message'} and p['stage'] == 'smoke' and p['code'] == 'unfilled_slot'
                  for p in answer['problems']), answer)
    check('and is not an error result (the tool worked)', not results_of(script.requests[2])[0].get('is_error'))
    check('finish after a change checks the draft itself, and the build is done',
          row['status'] == 'done' and row['usage']['checks'] == 2, (row['status'], row.get('error'), row['usage']))

    clean()
    unschooled = dict(FILES)
    unschooled['philosophy.yaml'] = FILES['philosophy.yaml'] + 'not_a_field: 1\n'
    script = Script(write_all(unschooled), say(use('finish', summary='Done.')),
                    say(use('write_file', path='philosophy.yaml', content=FILES['philosophy.yaml']),
                        use('finish', summary='Now done.')))
    row = run(script)
    refused = results_of(script.requests[2])[0]
    check('finish on a draft that does not pass is refused with the problems, and the build goes on',
          refused.get('is_error') and refused['content'].startswith('not finished') and '"problems"' in refused['content'],
          refused)
    check('a write and a finish in one turn run in order', row['status'] == 'done'
          and row['result']['summary'] == 'Now done.', row.get('error'))


def test_tools():
    print('the tools')
    clean()
    script = Script(
        say(use('write_file', path='../etc/passwd', content='x: 1\n'),
            use('write_file', path='training_contract.yaml', content='contracts: []\n'),
            use('write_file', path='philosophy.yaml', content='id: [unclosed\n'),
            use('write_file', path='philosophy.yaml'),
            use('write_file', path='philosophy.yaml', content='id: x\n', mode='w'),
            use('read_file', path='nothing.yaml'),
            use('get_schema', kind='philosophy'),
            use('launch_rocket')),
        write_all(),
        say(use('list_files'), use('read_file', path='philosophy.yaml'), use('get_schema', kind='vocabulary'),
            use('write_file', path='watch.yaml', content='defaults: {}\n'), use('delete_file', path='watch.yaml'),
            use('delete_file', path='watch.yaml')),
        say(use('decline', reason='Only testing.')))
    row = run(script)
    bad = results_of(script.requests[1])
    check('a path outside a package, a training contract, bad YAML: refused, each with why',
          all(r.get('is_error') for r in bad[:3]) and 'not a path' in bad[0]['content']
          and 'training contracts' in bad[1]['content'] and 'not YAML' in bad[2]['content'], [r['content'][:80] for r in bad[:3]])
    check('input that is not what the schema says comes back as INVALID_JSON, not run',
          all(r.get('is_error') and 'INVALID_JSON' in r['content'] for r in bad[3:5]), bad[3:5])
    check('a file that is not there, a schema not offered, a tool that does not exist: errors',
          all(r.get('is_error') for r in bad[5:]) and len(bad) == 8, bad[5:])
    good = results_of(script.requests[3])
    listed = json.loads(good[0]['content'])
    check('list_files, read_file, get_schema answer with the draft and the schema',
          sorted(f['path'] for f in listed) == sorted(FILES) and good[1]['content'] == FILES['philosophy.yaml']
          and '"$schema"' in good[2]['content'] and not any(r.get('is_error') for r in good[:5]), good[2]['content'][:80])
    check('delete_file removes a file once', good[4]['content'] == 'deleted: watch.yaml' and good[5].get('is_error'))
    check('decline ends the build with the model\'s sentence', row['status'] == 'failed'
          and row['error'] == {'code': 'declined', 'message': 'Only testing.'}, row['error'])
    check('and installs nothing', package_store.get_package(ME, PKG) is None)


def test_stops():
    print('turns that are not tool calls')
    clean()
    script = Script(say(text('I will look this up.'), {'type': 'server_tool_use', 'id': 'srv_1', 'name': 'web_search',
                                                        'input': {'query': 'atlas stone training'}}, stop='pause_turn',
                        server_tool_use={'web_search_requests': 1}),
                    write_all(), say(use('finish', summary='Done.')))
    row = run(script, {'description': DESCRIPTION, 'answers': ANSWERS, 'pastedText': 'Stones, then walking.',
                       'webSearch': True})
    first, second = script.requests[0], script.requests[1]
    web = [t for t in first['tools'] if t.get('type')]
    check('with web search allowed the request carries the two server tools, capped',
          [t['type'] for t in web] == ['web_search_20260209', 'web_fetch_20260209']
          and all(t['max_uses'] == 5 for t in web) and 'eager_input_streaming' not in web[0], web)
    opening = first['messages'][0]['content'][0]['text']
    check('and the first message says so, with the pasted text marked as material',
          'Web search and fetch are available' in opening and '<pasted_text>\nStones, then walking.\n</pasted_text>' in opening)
    check('a paused turn is sent back as it came, with no user message after it',
          second['messages'][-1]['role'] == 'assistant' and second['messages'][-1]['content'] == script_first_content(first, second)
          and row['status'] == 'done' and row['usage']['web_searches'] == 1, row.get('error'))

    clean()
    row = run(Script(say(stop='refusal', out=0)))
    check('a refusal ends the build in plain words', row['status'] == 'failed' and row['error']['code'] == 'refused'
          and 'other words' in row['error']['message'], row['error'])

    clean()
    half = use('write_file', path='philosophy.yaml')        # a call cut off before its content
    script = Script(say(half, stop='max_tokens'), write_all(), say(use('finish', summary='Done.')))
    row = run(script)
    after = script.requests[1]['messages']
    check('a turn cut off at the output limit is neither run nor kept; the model is told',
          len(after) == 1 and after[0]['role'] == 'user' and 'cut off' in after[0]['content'][-1]['text']
          and row['status'] == 'done', after)
    row = run(Script(*[say(half, stop='max_tokens')] * 3))
    check('three in a row end the build', row['status'] == 'failed' and row['error']['code'] == 'budget'
          and row['error']['spent'] == 'max_tokens', row['error'])

    clean()
    thinking = {'type': 'thinking', 'thinking': 'hm', 'signature': 'sig'}
    script = Script(say(thinking, stop='end_turn'), write_all(), say(use('finish', summary='Done.')))
    row = run(script)
    check('a turn that ends on thinking alone is not sent back',
          len(script.requests[1]['messages']) == 1 and row['status'] == 'done')

    clean()
    script = Script(say(text('Here is my plan.'), stop='end_turn'), write_all(),
                    say(thinking, text('All good.'), use('finish', summary='Done.')))
    row = run(script)
    nudge = script.requests[1]['messages']
    check('a turn of words alone is answered with a reminder to use the tools',
          [m['role'] for m in nudge] == ['user', 'assistant', 'user'] and 'call a tool' in nudge[-1]['content'][0]['text']
          and row['status'] == 'done')
    kept = [m for m in row['transcript'] if m['role'] == 'assistant'][-1]['content']
    check('thinking blocks go back unchanged, in place', kept[0] == thinking and kept[1] == text('All good.'), kept)
    row = run(Script(*[say(text('Still thinking aloud.'), stop='end_turn')] * 3))
    check('three in a row end the build', row['status'] == 'failed' and row['error']['code'] == 'stalled', row['error'])


def script_first_content(first, second):
    """The assistant turn the second request carries (the paused one)."""
    return second['messages'][len(first['messages'])]['content']


def test_budgets():
    print('budgets')
    clean()
    broken = dict(FILES)
    broken['exercises.yaml'] = 'exercises: []\n'
    script = Script(write_all(broken), say(use('check_package')), say(use('check_package')),
                    say(use('finish', summary='Done.')), say(use('list_files')))
    row = run(script, limits={'checks': 1, 'turns': 5})
    spent = results_of(script.requests[3])[0]
    check('past the limit a check is refused', spent.get('is_error') and spent['content'] == 'no checks left', spent)
    late = results_of(script.requests[4])[0]
    check('and so is a finish that would need one', late.get('is_error') and 'no checks are left' in late['content'], late)
    check('out of turns the build fails, in the athlete\'s words, with the problems it still had',
          row['status'] == 'failed' and row['error']['code'] == 'budget' and row['error']['spent'] == 'turns'
          and 'more simply' in row['error']['message'] and row['error']['problems']
          and set(row['error']['problems'][0]) == {'stage', 'code', 'file', 'message'}, row['error'])
    check('one check was paid for', row['usage']['checks'] == 1 and row['usage']['turns'] == 5, row['usage'])

    row = run(Script(write_all(out=5000)), limits={'output_tokens': 5000})
    check('the output-token budget ends a build', row['error']['code'] == 'budget'
          and row['error']['spent'] == 'output_tokens', row['error'])
    row = run(Script(), limits={'seconds': 0})
    check('and so does the clock', row['error']['code'] == 'budget' and row['error']['spent'] == 'seconds', row['error'])


def test_model_errors():
    print('the model cannot be asked')
    clean()
    row = run(Script(package_builder.ModelError('model_busy', 'The builder is busy. Try again in a few minutes.', '429')))
    check('a model error is a failed build with a sentence and the detail', row['status'] == 'failed'
          and row['error']['code'] == 'model_busy' and row['error']['detail'] == '429', row['error'])
    script = Script(package_builder.BadToolInput('bad json'), write_all(), say(use('finish', summary='Done.')))
    row = run(script)
    check('tool input the SDK could not parse: the same request is asked again',
          row['status'] == 'done' and script.requests[0]['messages'] == script.requests[1]['messages'])
    row = run(Script(*[package_builder.BadToolInput('bad json')] * 3))
    check('three times is a failed build', row['status'] == 'failed' and row['error']['code'] == 'model_output', row['error'])

    class Stream:
        def __init__(self, fail=None):
            self.fail = fail

        def __enter__(self):
            return self

        def __exit__(self, *exc):
            return False

        def __iter__(self):
            if self.fail:
                raise self.fail
            return iter([object(), object()])

        def get_final_message(self):
            class Message:
                def to_dict(self, mode='python'):
                    return {'content': [], 'stop_reason': 'end_turn', 'mode': mode}
            return Message()

    class Client:
        def __init__(self, stream):
            self.beta = self
            self.messages = self
            self._stream = stream
            self.asked = None

        def stream(self, **params):
            self.asked = params
            return self._stream

    beats = []
    package_builder._CLIENT = Client(Stream())
    try:
        message = package_builder._sdk_turn({'model': 'm'}, lambda: beats.append(1))
        check('the SDK turn streams, reports life per event and returns the final message as JSON',
              message == {'content': [], 'stop_reason': 'end_turn', 'mode': 'json'} and len(beats) == 2
              and package_builder._CLIENT.asked == {'model': 'm'})
        package_builder._CLIENT = Client(Stream(ValueError('Unterminated string')))
        try:
            package_builder._sdk_turn({}, lambda: None)
            check('unparseable tool input is BadToolInput', False)
        except package_builder.BadToolInput:
            check('unparseable tool input is BadToolInput', True)
    finally:
        package_builder._CLIENT = None


def test_resume():
    print('a process that dies mid-build')
    clean()
    request = {'description': DESCRIPTION, 'answers': ANSWERS, 'pastedText': '', 'webSearch': False}
    row = build_store.create(ME, request)
    claimed = build_store.claim_next()
    script = Script(write_all(), Crash())
    try:
        resume(script, claimed)
        check('the crash went through', False)
    except Crash:
        pass
    left = build_store.get(None, row['id'])
    check('the row keeps the turn that completed: transcript, draft, usage',
          left['status'] == 'running' and len(left['transcript']) == 3 and left['draft_files'] == FILES
          and left['usage']['turns'] == 1, (left['status'], len(left['transcript']), left['usage']))
    again = Script(say(use('check_package')), say(use('finish', summary='Done.')))
    done = resume(again, left)
    check('the next worker goes on from it: the first request carries the saved turns, not a new opening',
          again.requests[0]['messages'] == left['transcript'] and done['status'] == 'done', done.get('error'))
    check('and the usage carries on', done['usage']['turns'] == 3 and done['usage']['checks'] == 1, done['usage'])


def test_revise():
    print('a revision')
    clean()
    before = package_store.install(ME, FILES)['revision']
    request = {'description': 'Three walks instead of two.', 'answers': {}, 'pastedText': '', 'webSearch': False,
               'revise': {'packageId': PKG, 'note': 'Three walks instead of two.'}}
    renamed = dict(FILES)
    renamed['philosophy.yaml'] = FILES['philosophy.yaml'].replace(PKG, PKG + '_two', 1)
    changed = FILES['philosophy.yaml'] + '# revised\n'
    script = Script(say(use('write_file', path='philosophy.yaml', content=renamed['philosophy.yaml']), use('check_package')),
                    say(use('write_file', path='philosophy.yaml', content=changed), use('finish', summary='Three walks.')))
    row = run(script, request, draft=dict(FILES))
    opening = script.requests[0]['messages'][0]['content'][0]['text']
    check('the first message names the method, the note, and shows the files as installed',
          f'package `{PKG}`' in opening and 'Three walks instead of two.' in opening
          and '<file path="philosophy.yaml">' in opening and FILES['exercises.yaml'].strip() in opening
          and 'About the athlete: nothing given' in opening, opening[:400])
    answer = json.loads(results_of(script.requests[1])[1]['content'])
    check('a revision that renames its package does not pass', answer['ok'] is False
          and answer['problems'][0]['code'] == 'id_changed', answer['problems'][:1])
    stored = package_store.get_package(ME, PKG)
    check('the result is the same method, a revision on', row['status'] == 'done' and row['result']['packageId'] == PKG
          and row['result']['revision'] == before + 1 and stored['files']['philosophy.yaml'] == changed, row.get('error'))


def test_athlete_week():
    print('the week as the athlete')
    clean()
    request = {'description': DESCRIPTION, 'pastedText': '', 'webSearch': False,
               'answers': {'days': 9, 'minutes': '45', 'level': 'wizard', 'equipment': ['open_space', 7]}}
    check('answers that are not values the engine takes are left out',
          package_builder.answers_of(request) == {'equipment': ['open_space']}, package_builder.answers_of(request))
    script = Script(write_all(), say(use('check_package')), say(use('decline', reason='Enough.')))
    run(script, request)
    week = json.loads(results_of(script.requests[2])[0]['content']).get('for_this_athlete') or {}
    check('the week is generated with the athlete\'s equipment, and says what that left out',
          week.get('as', {}).get('equipment') == ['open_space'] and 'error' not in week
          and (week.get('feasible') is False or week.get('unfilled_slots') or week.get('unfilled_sessions')
               or week.get('substituted_sessions') or week.get('compromises')
               or any(s['exercises'] == 0 for s in week.get('week', []))), week)


def _week(number, phase, sessions, deload=False):
    return {'week_number': number, 'phase': 'build', 'phase_id': phase, 'phase_name': phase.title(),
            'is_deload': deload, 'schedule': {day: [s] for day, s in sessions.items()}}


def _session(name, *slots):
    return {'archetype': {'name': name}, 'modality': 'max_strength', 'exercises': [
        {'exercise': {'id': ex, 'name': ex.title()}, 'slot_role': ex, 'slot': slot, 'load': load}
        for ex, slot, load in slots]}


def test_program_text():
    print('the program in lines')
    squat = lambda kg, **slot: ('squat', slot, {'sets': 3, 'reps': 5, 'weight_kg': kg})   # noqa: E731
    weeks = [_week(1, 'first', {1: _session('Legs', squat(40.0)), 3: _session('Legs', squat(40.0))}),
             _week(2, 'first', {1: _session('Legs', squat(40.0)), 3: _session('Legs', squat(40.0))}),
             _week(3, 'first', {1: _session('Legs', squat(45.0)), 3: {**_session('Legs', squat(45.0)), 'exercises': [
                 {'exercise': None, 'slot_role': 'carry', 'slot': {}}]}}),
             _week(4, 'second', {1: _session('Legs', squat(40.0))})]
    text = package_builder._program_text(weeks)
    check('each week leads with its phase, each day with its session and every slot\'s numbers',
          'Week 1 · First (build)\n  Mon  Legs: Squat 3 × 5 @ 40 kg' in text, text)
    check('a day that repeats an earlier one and a week that repeats the last are said once',
          '  Wed  as Mon' in text and 'Week 2 · First (build) — the same as week 1' in text, text)
    check('an empty slot is named', '[carry: EMPTY]' in text, text)
    notes = package_builder._check_these(weeks)
    check('a load that starts again at a new phase is pointed out, with its numbers',
          len(notes) == 1 and 'Squat 45 kg in week 3, 40 kg in week 4' in notes[0] and 'one phase' in notes[0], notes)
    written = [_week(1, 'first', {1: _session('Press', ('press', {'load': '85% of training max'},
                                                        {'sets': 1, 'reps': 5, 'weight_kg': 40.0}))})]
    notes = package_builder._check_these(written)
    check('so is a written load the prescription does not carry, with what would carry it',
          len(notes) == 1 and '85% of training max' in notes[0] and 'prescription_policy: framework' in notes[0], notes)
    as_written = [_week(1, 'first', {1: _session('Press', ('press', {'load': '85% of training max'},
                                                           {'sets': 1, 'reps': 5, 'load_note': '85% of training max'}))})]
    check('and nothing is said when it does, where the line shows it',
          package_builder._check_these(as_written) == []
          and '(85% of training max)' in package_builder._program_text(as_written),
          package_builder._program_text(as_written))
    same = [_week(n, 'first', {1: _session('Legs', squat(40.0))}) for n in (1, 2, 3)] \
        + [_week(4, 'first', {1: _session('Legs', squat(40.0))}, deload=True)]
    notes = package_builder._check_these(same)
    check('and three weeks running with the same sessions and numbers', len(notes) == 1 and 'weeks 1–3' in notes[0], notes)
    deload = [_week(1, 'first', {1: _session('Legs', squat(50.0))}),
              _week(2, 'second', {1: _session('Legs', squat(45.0))}, deload=True)]
    check('a deload week\'s lighter load is not a restart', package_builder._check_these(deload) == [])
    long = package_builder._program_text([_week(n, 'first', {1: _session('Legs', squat(40.0 + n))}) for n in range(1, 900)])
    check('a program longer than a check shows is cut at a line, and says so',
          len(long) < package_builder.PROBE['chars'] + 80 and long.endswith('than a check shows)'), len(long))


def test_routes():
    print('through the routes and the worker')
    clean()
    package_builder.MODEL_TURN = Script(write_all(), say(use('check_package')), say(use('finish', summary='Stones and walks.')))
    build_worker.BUILDER = package_builder.build
    saved = package_builder.BEAT_SECONDS
    try:
        started = client.post('/api/methods/builds', json={'description': DESCRIPTION, 'answers': ANSWERS})
        build_worker.join(120)
        build_worker.drain()
        build = client.get(f"/api/methods/builds/{started.get_json()['build']['id']}").get_json()['build']
        check('a queued build runs to done on the model loop', started.status_code == 202 and build['status'] == 'done'
              and build['result']['summary'] == 'Stones and walks.' and build['progress']['checks'] == 1, build)
        methods = client.get('/api/methods').get_json()
        check('and the method is the athlete\'s', [m['id'] for m in methods['methods']] == [PKG], methods['methods'])

        clean()
        package_builder.BEAT_SECONDS = 0

        def cancelled_while_streaming(params):
            build_store.request_cancel(ME, build_store.active(ME)['id'])
            return write_all()
        slow = Script(cancelled_while_streaming)
        real = slow.__call__

        def turn(params, alive):
            message = real(params, lambda: None)
            alive()                      # the next sign of life from the stream sees the cancel
            return message
        package_builder.MODEL_TURN = turn
        started = client.post('/api/methods/builds', json={'description': DESCRIPTION, 'answers': ANSWERS})
        build_worker.join(120)
        build_worker.drain()
        build = client.get(f"/api/methods/builds/{started.get_json()['build']['id']}").get_json()['build']
        check('a cancel is seen while the model is still answering', build['status'] == 'cancelled', build)
    finally:
        package_builder.BEAT_SECONDS = saved
        package_builder.MODEL_TURN = None
    check('importing the API sets the model loop as the worker\'s builder and does not load the SDK',
          api._package_builder.build is package_builder.build)


def test_imports():
    print('what a server that never builds pays')
    import subprocess
    out = subprocess.run([sys.executable, '-c', 'import os; os.environ["SUPABASE_URL"]=""; os.environ["DATABASE_URL"]="";'
                          'import sys, api; from src import build_worker, package_builder;'
                          'print(build_worker.BUILDER is package_builder.build, "anthropic" in sys.modules)'],
                         capture_output=True, text=True, cwd=os.path.dirname(os.path.abspath(__file__)))
    check('the API starts with the builder set and the SDK not imported', out.stdout.strip().endswith('True False'),
          out.stdout[-200:] + out.stderr[-400:])
    import anthropic
    stream = anthropic.Anthropic(api_key='x').beta.messages.stream
    import inspect
    wanted = {'model', 'max_tokens', 'system', 'tools', 'messages', 'thinking', 'output_config', 'cache_control',
              'betas', 'fallbacks'}
    check('every parameter the loop sends is one the installed SDK takes',
          wanted <= set(inspect.signature(stream).parameters), wanted - set(inspect.signature(stream).parameters))


# ── The web's recorded answers ───────────────────────────────────────────────

FIXTURE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'frontend', 'src', 'mocks', 'fixtures', 'methods.json')


def _steady(value, names):
    """A recorded answer without what changes from run to run: build ids and
    timestamps become fixed ones."""
    if isinstance(value, dict):
        out = {}
        for k, v in value.items():
            if k in ('createdAt', 'updatedAt') and v:
                out[k] = '2026-11-13 10:00:00+00:00'
            elif k == 'id' and isinstance(v, str) and v in names:
                out[k] = names[v]
            elif k == 'revision' and isinstance(v, int):
                out[k] = 1
            elif k == 'remaining' and isinstance(v, int):
                out[k] = 4
            elif k == 'seconds' and 'inputTokens' in value:
                out[k] = 42.0
            else:
                out[k] = _steady(v, names)
        return out
    if isinstance(value, list):
        return [_steady(v, names) for v in value]
    return value


def _shape(value):
    """The keys of an answer, all the way down (a list by its first item)."""
    if isinstance(value, dict):
        return {k: _shape(v) for k, v in sorted(value.items())}
    if isinstance(value, list):
        return [_shape(value[0])] if value else []
    return type(value).__name__ if value is not None else 'null'


def recorded() -> dict:
    """What the routes answer through a method's life: a build running, done
    and failed, and the methods list while one runs and once it is built."""
    clean()
    for row in build_store.recent(ME, 50):
        if row['status'] in build_store.OPEN:
            build_store.finish(row['id'], 'cancelled')
    build_worker.BUILDER = package_builder.build
    broken = dict(FILES)
    broken['exercises.yaml'] = 'exercises: []\n'
    package_builder.MODEL_TURN = Script(write_all(broken), say(use('check_package')), say(use('list_files')))
    saved = dict(package_builder.LIMITS)
    package_builder.LIMITS['turns'] = 3
    try:
        failed = client.post('/api/methods/builds', json={'description': DESCRIPTION, 'answers': ANSWERS}).get_json()['build']['id']
        build_worker.join(120)
        build_worker.drain()
    finally:
        package_builder.LIMITS.update(saved)
    failed_build = client.get(f'/api/methods/builds/{failed}').get_json()

    # A build held at its second turn: what a client polling it sees.
    row = build_store.create(ME, {'description': DESCRIPTION, 'answers': ANSWERS, 'pastedText': '', 'webSearch': False})
    build_store.claim_next()
    build_store.save(row['id'], progress={'stage': 'writing', 'detail': '4 files written', 'turns': 2, 'checks': 0, 'files': 4,
                                          'problems': 0})
    running_build = client.get(f"/api/methods/builds/{row['id']}").get_json()
    while_running = client.get('/api/methods').get_json()
    package_builder.MODEL_TURN = Script(write_all(), say(use('check_package')),
                                        say(use('finish', summary='Two stone days and two easy walks a week, eight '
                                                'weeks. The stone work is kept light for the first fortnight.')))
    try:
        build_worker.run_build(build_store.get(None, row['id']))
    finally:
        package_builder.MODEL_TURN = None
    done_build = client.get(f"/api/methods/builds/{row['id']}").get_json()
    built = client.get('/api/methods').get_json()
    names = {failed: 'build-failed', row['id']: 'build-1'}
    return _steady({'running': running_build, 'done': done_build, 'failed': failed_build,
                    'methodsWhileRunning': while_running, 'methods': built,
                    'unavailable': {**built, 'available': False, 'reason': 'no_model_key'}}, names)


def test_fixture(write: bool):
    print("the web's recorded answers")
    fresh = recorded()
    if write:
        with open(FIXTURE, 'w', encoding='utf-8') as fh:
            json.dump(fresh, fh, indent=2, ensure_ascii=False)
            fh.write('\n')
        print(f'  wrote {os.path.relpath(FIXTURE)}')
        return
    try:
        with open(FIXTURE, encoding='utf-8') as fh:
            kept = json.load(fh)
    except OSError:
        kept = None
    check('frontend/src/mocks/fixtures/methods.json has the shape the routes answer with (--write re-records it)',
          kept is not None and _shape(kept) == _shape(fresh),
          'run: .venv/bin/python test_package_builder.py --write')
    check('a running build is the list\'s first build, and a built method is listed',
          fresh['methodsWhileRunning']['builds'][0]['status'] == 'running' and fresh['methods']['methods'][0]['id'] == PKG
          and fresh['done']['build']['result']['packageId'] == PKG and fresh['failed']['build']['error']['problems'])


# ── Dev Lab ▸ Builds ─────────────────────────────────────────────────────────

BUILDS_FIXTURE = os.path.join(os.path.dirname(FIXTURE), 'builds.json')


def _two_builds() -> tuple[str, str]:
    """A build that fixed what its first check found, and one that ran out of
    turns after a reply cut off at the output limit. → their ids."""
    clean()
    for row in build_store.recent(ME, 50):
        if row['status'] in build_store.OPEN:
            build_store.finish(row['id'], 'cancelled')
    broken = dict(FILES)
    broken['exercises.yaml'] = 'exercises: []\n'
    done = run(Script(
        say(text('I will write the four files first.'), *write_all(broken)['content'], out=4000, input_tokens=9000,
            cache_read_input_tokens=0, cache_creation_input_tokens=30000),
        say(use('check_package'), out=200),
        say({'type': 'thinking', 'thinking': '', 'signature': 's'}, text('The stone slots are empty: the exercises are missing.'),
            use('write_file', path='exercises.yaml', content=FILES['exercises.yaml']), out=1500),
        say(use('check_package'), out=150),
        say(use('finish', summary='Two stone days and two easy walks a week.'), out=120)))
    failed = run(Script(write_all(broken), say(text('…'), stop='max_tokens', out=32000), say(use('check_package')),
                        say(use('list_files'))),
                 request={'description': DESCRIPTION, 'answers': ANSWERS, 'pastedText': 'Stones, twice a week.',
                          'webSearch': True}, limits={'turns': 4})
    return done['id'], failed['id']


def test_build_report(write: bool):
    print('Dev Lab ▸ Builds: what a build did')
    from src import build_report
    done_id, failed_id = _two_builds()
    other = build_store.create('someone-else', {'description': DESCRIPTION, 'answers': {}})
    build_store.finish(other['id'], 'cancelled')

    listed = client.get('/api/dev/builds')
    body = listed.get_json()
    ids = [b['id'] for b in body['builds']]
    check('the list is the athlete\'s own builds, newest first, without draft or transcript',
          listed.status_code == 200 and ids[:2] == [failed_id, done_id] and other['id'] not in ids
          and not any(k in b for b in body['builds'] for k in ('transcript', 'draft_files', 'files', 'turns')), ids)
    done = next(b for b in body['builds'] if b['id'] == done_id)
    used = done['usage']
    check('each with what it spent', used['turns'] == 5 and used['checks'] == 2 and used['outputTokens'] == 5970
          and used['inputTokens'] == 9040 and used['cacheReadTokens'] == 4000 and used['cacheWriteTokens'] == 30000
          and used['model'] == 'scripted', used)
    price = package_builder.PRICE
    expected = (9040 * price['input_tokens'] + 5970 * price['output_tokens'] + 4000 * price['cache_read_input_tokens']
                + 30000 * price['cache_creation_input_tokens']) / 1e6
    check('and its cost at the model\'s list price', abs(done['costUsd'] - expected) < 0.0001, (done['costUsd'], expected))
    totals = body['totals']
    mine = [b for b in body['builds']]
    check('the totals are the listed builds\' sums', totals['builds'] == len(mine)
          and totals['outputTokens'] == sum(b['usage']['outputTokens'] for b in mine)
          and totals['byStatus'].get('done', 0) >= 1 and totals['byStatus'].get('failed', 0) >= 1
          and abs(totals['costUsd'] - sum(b['costUsd'] for b in mine)) < 0.01 and 0 < totals['doneShare'] < 1, totals)
    check('limit is honoured', len(client.get('/api/dev/builds?limit=1').get_json()['builds']) == 1)

    detail = client.get(f'/api/dev/builds/{done_id}').get_json()['build']
    turns, checks = detail['turns'], detail['checks']
    check('a build in full has its turns in order, each with its calls',
          [t['n'] for t in turns] == [1, 2, 3, 4, 5]
          and [c['tool'] for c in turns[0]['calls']] == ['write_file'] * len(FILES)
          and turns[0]['calls'][0]['bytes'] and turns[0]['calls'][0]['result'].startswith('written: ')
          and turns[0]['said'] == 'I will write the four files first.' and turns[2]['thought'] and not turns[0]['thought'],
          [(t['n'], [c['tool'] for c in t['calls']]) for t in turns])
    check('each turn has its own tokens', turns[0]['tokens'] == {'input': 9000, 'output': 4000, 'cacheRead': 0,
                                                                 'cacheWrite': 30000}
          and turns[4]['tokens']['output'] == 120, turns[0]['tokens'])
    check('the checks are the gate\'s answers: the problems first, then a pass',
          [c['ok'] for c in checks] == [False, True] and [c['turn'] for c in checks] == [2, 4]
          and checks[0]['problems'] and all(p['stage'] == 'smoke' and p['code'] == 'unfilled_slot' for p in checks[0]['problems'])
          and turns[1]['calls'][0]['check'] == 0 and turns[1]['calls'][0]['result'].endswith('to fix')
          and turns[3]['calls'][0]['result'] == 'passes' and checks[1]['checksLeft'] == package_builder.LIMITS['checks'] - 2,
          checks[0])
    athlete = checks[1]['athlete']
    check('with the program the model was shown for this athlete', athlete and athlete['feasible'] is True
          and athlete['as']['days_per_week'] == 4 and 'Week 1' in (athlete['program'] or ''), athlete)
    check('the problems counted by kind', detail['problemCounts'] and detail['problemCounts'][0]['code'] == 'unfilled_slot'
          and detail['problemCounts'][0]['count'] == len(checks[0]['problems']), detail['problemCounts'])
    check('the request as it was made, the files as installed, the limits in force',
          detail['request']['description'] == DESCRIPTION and detail['request']['answers'] == ANSWERS
          and {f['path']: f['content'] for f in detail['files']} == FILES
          and detail['limits'] == {'turns': 40, 'checks': 10, 'outputTokens': 200_000, 'seconds': 1500}
          and detail['result']['packageId'] == PKG and detail['effort'] == 'high', detail['limits'])

    failed = client.get(f'/api/dev/builds/{failed_id}').get_json()['build']
    check('a reply cut off at the output limit is counted and paid for but is no turn',
          failed['status'] == 'failed' and failed['error']['code'] == 'budget' and failed['usage']['turns'] == 4
          and len(failed['turns']) == 3 and len(failed['droppedTurns']) == 1
          and failed['droppedTurns'][0] == {'stop': 'max_tokens', 'tokens': {'input': 10, 'output': 32000,
                                                                              'cacheRead': 1000, 'cacheWrite': 0}}
          and failed['turns'][1]['tokens']['output'] == 100, (failed['usage'], failed['droppedTurns']))
    check('with what it asked for', failed['webSearch'] is True and failed['pastedChars'] == 21
          and failed['request']['pastedText'] == 'Stones, twice a week.')

    check('another athlete\'s build is not found', client.get(f"/api/dev/builds/{other['id']}").status_code == 404
          and client.get('/api/dev/builds/nothing').status_code == 404)
    os.environ['PACKAGE_BUILDER'] = 'off'
    try:
        check('and the routes are the builder\'s: off for an account it is off for',
              client.get('/api/dev/builds').status_code == 403 and client.get(f'/api/dev/builds/{done_id}').status_code == 403)
    finally:
        os.environ.pop('PACKAGE_BUILDER', None)

    old = build_report.conversation([{'role': 'user', 'content': 'x'},
                                     {'role': 'assistant', 'content': [use('finish', summary='Done.')]},
                                     {'role': 'user', 'content': [{'type': 'tool_result', 'tool_use_id': 'nope',
                                                                   'content': 'finished'}]}])
    check('a row from before per-turn tokens reads without them', old[0][0]['tokens'] is None
          and old[0][0]['calls'][0]['result'] == 'Done.' and old[1] == [] and old[2] == [])
    searched = build_report.conversation([
        {'role': 'user', 'content': [text('request')]},
        {'role': 'assistant', 'content': [{'type': 'server_tool_use', 'id': 's1', 'name': 'web_search',
                                           'input': {'query': '5/3/1 four days'}}]},
        {'role': 'assistant', 'content': [text('Nothing yet.')]},
        {'role': 'user', 'content': [text('Nothing is finished until you call a tool.')]}])[0]
    check('a web search is a call with its query, and the loop\'s nudge is a note on the turn before it',
          searched[0]['calls'][0]['tool'] == 'web_search' and searched[0]['calls'][0]['query'] == '5/3/1 four days'
          and searched[1]['note'] == 'Nothing is finished until you call a tool.' and searched[0]['note'] is None, searched)

    names = {done_id: 'build-1', failed_id: 'build-failed'}
    fresh = _steady({'list': {'builds': [b for b in body['builds'] if b['id'] in names], 'totals': build_report.totals(
                         [b for b in body['builds'] if b['id'] in names])},
                     'done': {'build': detail}, 'failed': {'build': failed}}, names)
    if write:
        with open(BUILDS_FIXTURE, 'w', encoding='utf-8') as fh:
            json.dump(fresh, fh, indent=2, ensure_ascii=False)
            fh.write('\n')
        print(f'  wrote {os.path.relpath(BUILDS_FIXTURE)}')
        return
    try:
        with open(BUILDS_FIXTURE, encoding='utf-8') as fh:
            kept = json.load(fh)
    except OSError:
        kept = None
    check('frontend/src/mocks/fixtures/builds.json has the shape the routes answer with (--write re-records it)',
          kept is not None and _shape(kept) == _shape(fresh), 'run: .venv/bin/python test_package_builder.py --write')


if __name__ == '__main__':
    for test in (test_built, test_fix_and_retry, test_tools, test_stops, test_budgets, test_model_errors, test_resume,
                 test_revise, test_athlete_week, test_program_text, test_routes, test_imports):
        test()
    test_fixture('--write' in sys.argv)
    test_build_report('--write' in sys.argv)
    clean()
    print()
    if FAILURES:
        print(f'{len(FAILURES)} FAILED:')
        for f in FAILURES:
            print('  -', f)
        sys.exit(1)
    print('all package builder checks passed')
