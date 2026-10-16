"""GET /progression/review's compliance counts the sessions whose day has
come, as the Program tab's scorecard does — not the whole current week. By
Wednesday of week 1, two of two sessions done read 50% (two more were still to
come on Friday and Sunday) beside the Program tab's 100%. No database.
"""
import os
os.environ.setdefault('SUPABASE_URL', '')
from datetime import date, timedelta

from src import progression_tracker as pt
from src.analytics import review as rv

DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']


def week(n, days):
    return {'week_number': n, 'schedule': {d: [{'modality': 'aerobic_base', 'exercises': []}] for d in days}}


def test_due_sessions_stop_at_today():
    program = {'program_start_date': '2026-10-12', 'weeks': [week(1, ['Tuesday', 'Wednesday', 'Friday', 'Sunday']),
                                                             week(2, ['Tuesday'])]}
    due = pt._due_sessions(program, program['weeks'], today=date(2026, 10, 15))   # a Thursday
    assert sorted(due) == [(1, 'Tuesday', 0), (1, 'Wednesday', 0)]
    assert len(pt._due_sessions(program, program['weeks'], today=date(2026, 10, 20))) == 5
    assert pt._due_sessions(program, program['weeks'], today=date(2026, 10, 12)) == []


def test_no_start_date_counts_everything():
    program = {'weeks': [week(1, ['Monday', 'Friday'])]}
    assert len(pt._due_sessions(program, program['weeks'], today=date(2026, 10, 15))) == 2


def test_review_compliance_is_done_over_due():
    today = date.today()
    monday = today - timedelta(days=today.weekday())
    program = {'program_start_date': monday.isoformat(), 'weeks': [week(1, DAYS)]}
    done_so_far = DAYS[:today.weekday() + 1]
    logs = {f'1-{d}-0': {'completedAt': 'x'} for d in done_so_far}
    review = pt.compute_progression_review(user_id='u', program=program, bio_logs=[], session_logs=logs)
    assert review['compliance_pct'] == 100, review['compliance_pct']
    logs.pop(f'1-{today.strftime("%A")}-0')
    review = pt.compute_progression_review(user_id='u', program=program, bio_logs=[], session_logs=logs)
    assert review['compliance_pct'] == round(len(done_so_far[:-1]) / len(done_so_far) * 100)



def test_scorecard_completion_wins():
    """Moving Friday to Saturday minted a new version; Tuesday's and
    Wednesday's logs stayed with the old one, so this version's logs were
    empty and Progress read 0 % beside Today's 2 of 2. The route passes the
    scorecard's count, which matches logs by date."""
    program = {'program_start_date': '2026-10-12', 'weeks': [week(1, ['Tuesday', 'Wednesday', 'Saturday'])]}
    review = pt.compute_progression_review(user_id='u', program=program, bio_logs=[], session_logs={},
                                           completion=(2, 2))
    assert review['compliance_pct'] == 100, review['compliance_pct']
    assert 'low_compliance' not in review['flags']
    assert not any('completion rate is low' in r for r in review['recommendations'])
    assert not any(a.get('type') == 'rebuild_habit' for a in review.get('adjustments', []))
    review = pt.compute_progression_review(user_id='u', program=program, bio_logs=[], session_logs={},
                                           completion=(1, 2))
    assert review['compliance_pct'] == 50




def test_missed_sessions_are_said_without_lift_data():
    """No set data yet, 2 of 7 done: the early return used to drop the
    low-completion advice, and the phone said "nothing to change"."""
    program = {'program_start_date': '2026-10-12', 'weeks': [week(1, DAYS)]}
    review = pt.compute_progression_review(user_id='u', program=program, bio_logs=[], session_logs={},
                                           completion=(2, 7))
    assert 'low_compliance' in review['flags']
    assert any('completion rate is low' in r for r in review['recommendations'])
    assert [a['type'] for a in review['adjustments']] == ['rebuild_habit']
    out = rv.explain(review, _doc(2, 7))
    assert out['recommendations'] == ['Session completion rate is low — prioritise showing up over intensity.']


# ── The score explained (src/analytics/review.py) ──────────────────────────


def _doc(completed, planned, weeks=1, progress=()):
    return {'scorecard': {'completedSessions': completed, 'plannedSessions': planned, 'elapsedWeeks': weeks},
            'progress': list(progress)}


def _finding(fid, status, name=None):
    return {'exercise_id': fid, 'name': name or fid, 'status': status, 'change_summary': ''}


def _pr(pid, primitive='set_load', series=(), planned=4, in_scope=0, next_date=None):
    return {'id': pid, 'label': pid.title(), 'primitive': primitive, 'series': list(series),
            'status': 'insufficient_data', 'coverage': {'inScope': in_scope, 'measured': 0},
            'programScope': {'planned': planned, 'nextDate': next_date}}


def test_week_one_scores_sessions_only():
    """Two of two done and one measure with one point: the old formula said
    70 (a neutral 50 for the measure), exactly the On Track line."""
    doc = _doc(2, 2, progress=[_pr('skills', 'unlocks', series=[{'week': 1, 'value': 0}], planned=17, in_scope=1)])
    out = rv.explain({'compliance_pct': 100, 'exercise_findings': [_finding('skills', 'insufficient_data')],
                      'flags': ['insufficient_data'],
                      'recommendations': ['Log at least 2 sessions with set data to see progression analysis.']}, doc)
    assert out['overall_score'] == 100
    assert out['score_breakdown']['basis'] == 'compliance_only'
    assert out['score_breakdown']['waiting'] == 1
    assert out['score_status']['label'] == 'On Track'
    assert out['score_status']['reason'] == 'Every session due so far is done; no lift or skill trend yet.'
    assert out['scope_label'] == '2 of 2 sessions so far · week 1'
    assert out['flags'] == [] and out['recommendations'] == []
    f = out['exercise_findings'][0]
    assert f['description'].startswith('Movements practised') and f['waiting_for'].startswith('1 of 2')
    assert out['pending_measures'] == [], 'a measure with a point is a finding, not waiting'


def test_measured_trends_join_the_score():
    out = rv.explain({'compliance_pct': 100, 'exercise_findings': [
        _finding('a', 'on_track'), _finding('b', 'insufficient_data')]}, _doc(4, 4, weeks=2))
    assert out['overall_score'] == round(100 * 0.4 + 80 * 0.6)
    assert [p['points'] for p in out['score_breakdown']['parts']] == [40, 48]
    assert '1 still collecting data' in out['score_breakdown']['summary']


def test_status_names_what_is_stalled():
    out = rv.explain({'compliance_pct': 50, 'exercise_findings': [
        _finding('swing', 'stalled', 'Two-hand swing'), _finding('press', 'on_track', 'Press')]}, _doc(2, 4, weeks=2))
    assert out['overall_score'] == round(50 * 0.4 + 50 * 0.6)          # stalled 20, on track 80
    assert out['score_status']['id'] == 'mixed'
    assert out['score_status']['reason'] == '2 of 4 sessions due so far are done; 1 stalled (Two-hand swing), 1 on track.'
    assert [b['min'] for b in out['score_status']['bands']] == [70, 45, 0]


def test_nothing_due_has_no_score():
    out = rv.explain({'compliance_pct': 0, 'exercise_findings': []}, _doc(0, 0))
    assert out['overall_score'] is None and out['score_status'] is None
    assert out['scope_label'] == 'No session due yet'


def test_pending_measures_say_how_to_start():
    doc = _doc(2, 2, progress=[
        _pr('ballistic_load', planned=6, in_scope=0, next_date='2026-10-19'),
        _pr('logged_but_bare', planned=6, in_scope=2),
        _pr('jerk_rpm', 'rate', planned=0),                        # not in this track: never listed
    ])
    out = rv.explain({'compliance_pct': 100, 'exercise_findings': []}, doc, today=date(2026, 10, 16))
    got = {p['id']: p for p in out['pending_measures']}
    assert set(got) == {'ballistic_load', 'logged_but_bare'}
    assert got['ballistic_load']['reason'] == 'None of the sessions it measures has come up yet — the next is Mon 19 Oct.'
    assert 'log reps and kg per set' in got['logged_but_bare']['reason']
    assert got['ballistic_load']['needs'][0]['label'] == 'Reps and kg per set'



def test_breakdown_names_each_measure():
    review = {'compliance_pct': 100, 'exercise_findings': [
        {'exercise_id': 'back_squat', 'name': 'Back squat', 'status': 'on_track', 'change_summary': '+5kg over 2 wk'},
        {'exercise_id': 'skills', 'name': 'Movements earned', 'status': 'insufficient_data',
         'change_summary': '+0 exercises over 1 wk'}]}
    doc = {'scorecard': {'completedSessions': 4, 'plannedSessions': 4, 'elapsedWeeks': 2}, 'progress': []}
    got = rv.explain(review, doc)['score_breakdown']['measures']
    assert [m['name'] for m in got] == ['Back squat', 'Movements earned']
    assert got[0]['points'] == 80 and got[0]['detail'] == '+5kg over 2 wk'
    assert got[1]['points'] is None, 'a measure still collecting adds no points'
    assert got[1]['detail'], 'and says how far it is from a trend'


def test_exercises_scheduled_by_today():
    # The Progress tab's "so far": only sessions whose day has come, by the
    # week's array index (week 2 is numbered 9 here, as after a regenerate).
    def ex(i):
        return {'exercise': {'id': i}}
    weeks = [{'week_number': 8, 'schedule': {'Monday': [{'exercises': [ex('swing'), {'meta': True}]}],
                                            'Friday': [{'exercises': [ex('press')]}]}},
             {'week_number': 9, 'schedule': {'Monday': [{'exercises': [ex('snatch')]}]}}]
    assert pt.exercises_scheduled_by(weeks, '2026-10-12', '2026-10-15') == {'swing'}
    assert pt.exercises_scheduled_by(weeks, '2026-10-12', '2026-10-19') == {'swing', 'press', 'snatch'}
    assert pt.exercises_scheduled_by(weeks, None, '2026-10-19') == set(), 'no start date: nothing is due'


if __name__ == '__main__':
    for name, fn in list(globals().items()):
        if name.startswith('test_'):
            fn(); print('ok', name)
    print('all passed')
