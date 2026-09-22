#!/usr/bin/env python
"""The stored program must always keep its envelope.

POST /api/programs/generate used to auto-save its own response — the bare
GeneratedProgram — straight into program_data. That wiped programStartDate and
left no `currentProgram` key, which every client reads, so a real account's
program silently read as "no program" while all 18 weeks sat intact in the
database.

Needs a local PostgreSQL; skips cleanly (exit 0) without one.

    brew services start postgresql@14 && createdb training_test
    .venv/bin/python test_program_envelope.py
"""
import os, sys, json
TEST_DSN = 'postgresql://localhost:5432/training_test?sslmode=disable'
import psycopg2
try: psycopg2.connect(TEST_DSN).close()
except Exception as e: print('no local pg, skipping:', e); sys.exit(0)
os.environ['DATABASE_URL'] = TEST_DSN; os.environ['SUPABASE_URL'] = ''
sys.path.insert(0, '/Users/cesarhaerdfeldt/programming/training')
import api
from src.db import save_user_program, get_user_program

conn = psycopg2.connect(TEST_DSN); conn.autocommit = True
with conn.cursor() as c:
    c.execute("""DROP TABLE IF EXISTS user_programs;
                 CREATE TABLE user_programs (user_id TEXT PRIMARY KEY,
                   program_data JSONB, created_at TIMESTAMPTZ DEFAULT NOW(),
                   updated_at TIMESTAMPTZ DEFAULT NOW());""")
U = 'heal-test-user'

# Exactly the shape found in production: bare GeneratedProgram, no envelope.
bare = {
    'goal': {'id': '_phil_wildman_kettlebell', 'name': 'Mark Wildman Kettlebell'},
    'weeks': [{'week_number': 1, 'phase': 'base', 'schedule': {'Monday': []}}],
    'constraints': {}, 'validation': {}, 'compromises': [],
    'volume_summary': [], 'coverage_report': {},
}
save_user_program(U, bare)

stored = get_user_program(U)
print('before heal — top keys:', sorted(stored.keys()))
assert 'currentProgram' not in stored

get = api.get_user_program_endpoint.__wrapped__
with api.app.test_request_context('/api/user/program'):
    from flask import g; g.user_id = U
    out = json.loads(get().get_data(as_text=True))

print('response  — top keys:', sorted(out.keys()))
assert out.get('currentProgram'), 'currentProgram missing from response'
assert len(out['currentProgram']['weeks']) == 1
assert out['sourceGoalIds'] == ['wildman_kettlebell'], out['sourceGoalIds']
print('  sourceGoalIds recovered from goal id:', out['sourceGoalIds'])
print('  programStartDate:', out['programStartDate'], '(null by design — unrecoverable)')

persisted = get_user_program(U)
print('after heal — stored keys:', sorted(persisted.keys()))
assert 'currentProgram' in persisted, 'repair was not persisted'
assert persisted['currentProgram']['goal']['name'] == 'Mark Wildman Kettlebell'

# A healthy row must pass through untouched.
healthy = {'currentProgram': {'weeks': [], 'goal': {'id': 'x'}},
           'programStartDate': '2026-05-04', 'eventDate': None,
           'sourceGoalIds': ['uphill_athlete'], 'sourceGoalWeights': {}}
save_user_program(U, healthy)
with api.app.test_request_context('/api/user/program'):
    from flask import g; g.user_id = U
    out2 = json.loads(get().get_data(as_text=True))
assert out2['programStartDate'] == '2026-05-04', out2['programStartDate']
assert out2['sourceGoalIds'] == ['uphill_athlete']
print('healthy row untouched — start date preserved:', out2['programStartDate'])

# And the generate auto-save must now write an envelope.
env = api._wrap_generated_program(bare, {'philosophy_id': 'wildman_kettlebell'},
                                  {'programStartDate': '2026-01-12'})
print('\nwrap_generated_program ->', sorted(env.keys()))
assert env['currentProgram']['goal']['name'] == 'Mark Wildman Kettlebell'
assert env['programStartDate'] == '2026-01-12', 'existing start date must survive regeneration'
assert env['sourceGoalIds'] == ['wildman_kettlebell']
print('  existing start date preserved through regeneration:', env['programStartDate'])
env2 = api._wrap_generated_program(bare, {}, None)
print('  first-ever generate gets today:', env2['programStartDate'])
assert env2['sourceGoalIds'] == ['wildman_kettlebell'], 'ids recovered from goal id'

print('\nALL HEAL ASSERTIONS PASSED')


# --- persist is opt-in -------------------------------------------------------
# A generate that does not ask to persist must leave the stored program alone.
# The web app saves through PUT /api/user/program itself; iOS sends persist.
save_user_program(U, healthy)
before = get_user_program(U)

gen = api.generate_program.__wrapped__
import flask
# `philosophy_id`, not `goal_id` — see _generate_program_inner.
body_no_persist = {'philosophy_id': 'wildman_kettlebell',
                   'constraints': {'training_level': 'intermediate', 'days_per_week': 3,
                                   'session_time_minutes': 45,
                                   'equipment': ['kettlebell', 'pull_up_bar']},
                   'num_weeks': 2}
with api.app.test_request_context('/api/programs/generate', method='POST', json=body_no_persist):
    from flask import g
    g.user_id = U
    try:
        gen()
    except Exception as e:
        print('  (generate raised, which is fine for this assertion):', type(e).__name__)
after = get_user_program(U)
assert after == before, 'a non-persisting generate must not touch the stored program'
print('non-persisting generate left the stored program untouched')

with api.app.test_request_context('/api/programs/generate', method='POST',
                                  json={**body_no_persist, 'persist': True}):
    from flask import g
    g.user_id = U
    try:
        gen()
    except Exception as e:
        print('  (generate raised:', type(e).__name__, ')')
after2 = get_user_program(U)
if after2 != before:
    assert 'currentProgram' in after2, 'persisted write must keep the envelope'
    assert after2.get('programStartDate') == '2026-05-04', \
        'an existing start date must survive a persisting regenerate'
    print('persisting generate wrote an envelope and kept the start date:',
          after2['programStartDate'])
else:
    raise AssertionError('persisting generate did not write anything — '
                         'the main assertion of this test would be vacuous')

with conn.cursor() as c: c.execute('DROP TABLE IF EXISTS user_programs')
print('\nPERSIST OPT-IN ASSERTIONS PASSED')
