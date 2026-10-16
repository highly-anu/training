"""GET /progression/review's compliance counts the sessions whose day has
come, as the Program tab's scorecard does — not the whole current week. By
Wednesday of week 1, two of two sessions done read 50% (two more were still to
come on Friday and Sunday) beside the Program tab's 100%. No database.
"""
import os
os.environ.setdefault('SUPABASE_URL', '')
from datetime import date, timedelta

from src import progression_tracker as pt

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


if __name__ == '__main__':
    for name, fn in list(globals().items()):
        if name.startswith('test_'):
            fn(); print('ok', name)
    print('all passed')
