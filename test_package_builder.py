#!/usr/bin/env python
"""The model loop that writes an athlete's method (docs/roadmap.md 21.3):
src/package_builder.py.

No model is called: `package_builder.MODEL_TURN` — the one place a request
leaves the process — is a script here, answering each request with the turn a
case needs (tool calls, a pause, a refusal, a cut-off). Everything else is
real: the tools, the gates on the draft (the from-scratch test package,
test_packages/scratch_minimal), the worker, the store, the install and the
routes.

Run: SUPABASE_URL='' .venv/bin/python test_package_builder.py
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


if __name__ == '__main__':
    for test in (test_built, test_fix_and_retry, test_tools, test_stops, test_budgets, test_model_errors, test_resume,
                 test_revise, test_athlete_week, test_routes, test_imports):
        test()
    clean()
    print()
    if FAILURES:
        print(f'{len(FAILURES)} FAILED:')
        for f in FAILURES:
            print('  -', f)
        sys.exit(1)
    print('all package builder checks passed')
