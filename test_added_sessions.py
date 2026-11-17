"""On-the-fly sessions: a session the athlete adds to a rest day (or any day from
today on). `POST /api/sessions/generate` with `add: true` picks it from any
package, whatever builds the program (a training contract, a week template),
and marks it `added`; an added session counts only once it is done.

    SUPABASE_URL='' .venv/bin/python test_added_sessions.py
"""
from __future__ import annotations

import os
import sys
import unittest
from datetime import date, timedelta
from unittest import mock

os.environ.setdefault('SUPABASE_URL', '')
os.environ.setdefault('DATABASE_URL', '')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import api  # noqa: E402
from src import phase_summary, program_history as ph  # noqa: E402
from src.analytics.context import AnalyticsInputs, Context  # noqa: E402
from src.analytics import scorecard  # noqa: E402

BODY = {'modality': 'mobility', 'phase': 'base', 'week_in_phase': 1, 'add': True,
        'constraints': {'session_time_minutes': 30, 'training_level': 'intermediate',
                        'equipment': ['kettlebell', 'pull_up_bar', 'open_space']}}


def stored(goal: dict) -> dict:
    return {'currentProgram': {'goal': goal, 'weeks': []}}


class AddRoute(unittest.TestCase):
    def setUp(self):
        self.client = api.app.test_client()

    def post(self, body, program=None):
        with mock.patch('src.db.get_user_program', return_value=program or stored({})):
            return self.client.post('/api/sessions/generate', json=body)

    def test_an_added_mobility_session_from_any_package_is_badged(self):
        resp = self.post(BODY, stored({'primary_sources': ['starting_strength']}))
        self.assertEqual(resp.status_code, 200, resp.get_json())
        out = resp.get_json()
        self.assertTrue(out['added'])
        self.assertEqual(out['modality'], 'mobility')
        self.assertEqual(out['archetype']['modality'], 'mobility')
        prov = out['provenance']
        self.assertTrue(prov['borrowed'], 'Starting Strength writes no mobility session')
        self.assertIn(prov['package'], ('kelly_starrett', 'atg'))
        self.assertTrue(prov.get('label'))

    def test_the_programs_own_package_is_not_borrowed(self):
        out = self.post({**BODY, 'archetype_id': None}, stored({'primary_sources': ['kelly_starrett', 'atg']}))
        prov = out.get_json()['provenance']
        self.assertFalse(prov['borrowed'])

    def test_a_contract_program_does_not_refuse_an_extra(self):
        with mock.patch.object(api, '_stored_contract', return_value='wildman_kettlebell/general_practice@1'):
            self.assertEqual(self.post({**BODY, 'add': False}).status_code, 422, 'replacing still refuses')
            self.assertEqual(self.post(BODY).status_code, 200, 'adding does not')

    def test_a_templated_framework_adds_by_modality_not_by_day(self):
        out = self.post({**BODY, 'framework_id': 'concurrent_training'}).get_json()
        self.assertTrue(out['added'])
        self.assertEqual(out['archetype']['modality'], 'mobility')
        self.assertNotIn('category', out)

    def test_a_phase_no_session_names_still_finds_one(self):
        out = self.post({**BODY, 'phase': 'no_such_kind'})
        self.assertEqual(out.status_code, 200, out.get_json())

    def test_nothing_fits_says_so_in_words(self):
        resp = self.post({**BODY, 'modality': 'no_such_modality'})
        self.assertEqual(resp.status_code, 422)
        self.assertIn('no such modality', resp.get_json()['detail'])


START = date(2026, 10, 5)            # a Monday
TODAY = START + timedelta(days=9)    # week 2, Wednesday


def program(extra_done=False, extra_on=TODAY - timedelta(days=1)):
    plain = {'modality': 'max_strength', 'archetype': {'id': 'a', 'modality': 'max_strength'}, 'exercises': []}
    extra = {'modality': 'mobility', 'archetype': {'id': 'm', 'modality': 'mobility'}, 'exercises': [],
             'added': True}
    weeks = []
    for wi in range(2):
        sched = {'Monday': [dict(plain)], 'Thursday': [dict(plain)]}
        weeks.append({'week_number': wi + 1, 'phase': 'base', 'schedule': sched})
    day = extra_on.strftime('%A')
    wi = (extra_on - START).days // 7
    weeks[wi]['schedule'].setdefault(day, []).append(extra)
    logs = {}
    if extra_done:
        idx = len(weeks[wi]['schedule'][day]) - 1
        logs[f'{wi + 1}-{day}-{idx}'] = {'completedAt': f'{extra_on.isoformat()}T18:00:00Z'}
    return {'goal': {}, 'weeks': weeks}, logs


class ExtrasCountOnlyWhenDone(unittest.TestCase):
    def ctx(self, done):
        prog, logs = program(extra_done=done)
        return Context(AnalyticsInputs(prog, START, TODAY, logs), frameworks={})

    def test_a_skipped_extra_is_no_missed_session(self):
        hits = list(self.ctx(False).sessions())
        self.assertFalse(any(h['session'].get('added') for h in hits))
        self.assertEqual(len(hits), 3, 'week 1 Mon, Thu; week 2 Mon')

    def test_a_done_extra_counts(self):
        ctx = self.ctx(True)
        hits = list(ctx.sessions())
        extras = [h for h in hits if h['session'].get('added')]
        self.assertEqual(len(extras), 1)
        self.assertTrue(ctx.completed(extras[0]))

    def test_this_weeks_total_leaves_out_an_undone_extra(self):
        self.assertEqual(scorecard._current_week(self.ctx(False), {1: 1}, {1: 0})['total'], 2)
        self.assertEqual(scorecard._current_week(self.ctx(True), {1: 2}, {1: 1})['total'], 3)

    def test_the_phase_summary_never_holds_an_extra(self):
        prog, _ = program(extra_done=True)
        stripped = phase_summary.without_added(prog['weeks'])
        self.assertFalse(any(s.get('added') for w in stripped for ss in w['schedule'].values() for s in ss))
        self.assertTrue(any(s.get('added') for w in prog['weeks'] for ss in w['schedule'].values() for s in ss),
                        'the stored weeks keep it')

    def test_the_watchs_week_counts_an_extra_once_done(self):
        prog, _ = program()
        weeks = prog['weeks']
        tue = (TODAY - timedelta(days=1)).strftime('%A')
        with mock.patch.object(api, '_cached_headline', return_value=None, create=True):
            for done, total in ((False, 2), (True, 3)):
                is_done = (lambda wi, d, i, done=done: done and d == tue)
                try:
                    out = api._watch_progress('u', prog, weeks, START, TODAY, 1, is_done)
                except Exception as e:  # the headline read needs no DB here
                    self.fail(f'_watch_progress raised {e!r}')
                self.assertEqual(out['week']['sessions'], total, f'done={done}')


class HistoryCarriesOn(unittest.TestCase):
    """Adding to today or later is the same block carrying on; a past day would
    switch the plan, which is why the clients offer today and later only."""

    def env(self, weeks):
        return {'currentProgram': {'goal': {}, 'weeks': weeks}, 'programStartDate': START.isoformat()}

    def rows(self, weeks):
        env = self.env(weeks)
        return ph.flatten_program(ph.version_id('u', env), env)

    def test_an_extra_on_today_continues_one_on_a_past_day_does_not(self):
        plain, _ = program(extra_done=False, extra_on=TODAY)
        base = [{**w, 'schedule': {d: [x for x in ss if not x.get('added')] for d, ss in w['schedule'].items()}}
                for w in plain['weeks']]
        today_rows = self.rows(plain['weeks'])
        self.assertNotEqual(ph.skeleton_hash(self.env(base)), ph.skeleton_hash(self.env(plain['weeks'])),
                            'an extra is a new version of the plan')
        div = ph.divergence_date(self.rows(base), today_rows, START)
        self.assertEqual(div, TODAY)
        self.assertIsNotNone(ph.carry_over_until(TODAY, div), 'today: the block carries on')
        past, _ = program(extra_done=False, extra_on=TODAY - timedelta(days=2))
        div = ph.divergence_date(self.rows(base), self.rows(past['weeks']), START)
        self.assertIsNone(ph.carry_over_until(TODAY, div), 'a past day switches the plan')

    def test_the_added_session_gets_a_row_of_its_own(self):
        plain, _ = program(extra_done=False, extra_on=TODAY)
        rows = [r for r in self.rows(plain['weeks']) if r['day_name'] == TODAY.strftime('%A')]
        self.assertEqual(len(rows), 1)
        self.assertTrue(rows[0]['session_uid'].endswith(f"-{TODAY.strftime('%A')}-0"))


if __name__ == '__main__':
    unittest.main(verbosity=1)
