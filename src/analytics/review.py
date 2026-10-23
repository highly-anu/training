"""What GET /api/progression/review says about its own number.

The score answers one question — is the training working? — so it is the
trend of the methodology's own measures and nothing else: the mean of each
measured finding's status points. Until one measure has a trend there is no
score, and the breakdown says what is still collecting.

It was compliance × 0.4 + trends × 0.6 (and before that, a finding with no
data counted as a neutral 50 — week 1's exactly-70 "On Track"). Completion
inside the score repeated Today's Adherence card and the Program tab, and
until a measure had a trend the score *was* completion: two cards, one
number. Since 2026-10-16 completion is context beside the score
(`compliance_pct`, `scope_label`), never part of it.

Everything a client shows about the score is built here — the sum, the
status band and why, what the compliance covers, the measures still waiting
for data and how to start them — so the web and the phone cannot word it
differently (the web's widget called the low band "Behind", the phone "Off
Track"). Pure; `test_progression_review.py` runs it on hand-built documents.
"""
from __future__ import annotations

from datetime import date

from src.analytics import vocabulary

STATUS_POINTS = {'ahead': 100, 'on_track': 80, 'behind': 40, 'stalled': 20}

BANDS = [
    {'id': 'on_track', 'label': 'On Track', 'min': 70},
    {'id': 'mixed', 'label': 'Mixed', 'min': 45},
    {'id': 'off_track', 'label': 'Off Track', 'min': 0},
]

PURPOSE = ("Is the training working? Your methodology's own measures over time — lifts, skills, "
           'minutes — scored by their trends. How much of the plan you have done is the Scorecard below.')


def band(score: int) -> dict:
    return next(b for b in BANDS if score >= b['min'])


def explain(review: dict, doc: dict | None, *, today: date | None = None) -> dict:
    """The review with its score recomputed and explained. Additive: every
    key an older client reads keeps its meaning (`overall_score` is still
    0–100, or None before any session was due)."""
    today = today or date.today()
    sc = (doc or {}).get('scorecard') or {}
    completed = int(sc.get('completedSessions') or 0)
    scheduled = int(sc.get('plannedSessions') or 0)
    weeks = int(sc.get('elapsedWeeks') or 0)
    compliance = int(review.get('compliance_pct') or 0)

    findings = review.get('exercise_findings') or []
    _describe_findings(findings, doc)
    measured = [f for f in findings if f.get('status') in STATUS_POINTS]

    if scheduled == 0 and not doc:
        # No scorecard to say what was due: keep the tracker's own verdict.
        return review
    trends = None
    if scheduled == 0:
        score = None
        basis = 'not_started'
    elif measured:
        trends = round(sum(STATUS_POINTS[f['status']] for f in measured) / len(measured))
        score = trends
        basis = 'trends'
    else:
        score = None
        basis = 'collecting'

    review['overall_score'] = score
    review['score_breakdown'] = _breakdown(basis, compliance, completed, scheduled,
                                           measured, findings, trends)
    review['score_status'] = _status(score, compliance, completed, scheduled, measured) if score is not None else None
    review['scope_label'] = (f'{completed} of {scheduled} session{"" if scheduled == 1 else "s"} so far'
                             f' · week {max(weeks, 1)}') if scheduled else 'No session due yet'
    review['pending_measures'] = _pending(doc, today)
    review['purpose'] = PURPOSE
    # The tracker's "insufficient_data" flag meant "no score"; the review now
    # says itself why there is none (`score_breakdown.basis`), and its advice
    # — consistency above all — holds from the first session due.
    if scheduled:
        review['flags'] = [f for f in review.get('flags') or [] if f != 'insufficient_data']
        review['recommendations'] = [r for r in review.get('recommendations') or []
                                     if not r.startswith('Log at least 2 sessions with set data')]
    return review


def _breakdown(basis, compliance, completed, scheduled, measured, findings, trends) -> dict:
    waiting = len(findings) - len(measured)
    if basis == 'trends':
        summary = (f'The mean of {len(measured)} measure{"" if len(measured) == 1 else "s"} with a trend: '
                   f'{trends}' + (f'; {waiting} still collecting data' if waiting else '') + '. '
                   'Ahead 100, on track 80, behind 40, stalled 20.')
        parts = [{'id': 'trends', 'label': 'Measure trends', 'value': trends, 'weight': 1.0, 'points': trends}]
    elif basis == 'collecting':
        summary = ('No measure has a trend yet, so there is no score. A measure counts once it has data '
                   f'from 2 sessions ({completed} of {scheduled} sessions due so far are done).')
        parts = []
    else:
        summary = 'No session was due yet, so there is nothing to score.'
        parts = []
    # What the trends part is made of, one line per measure: inside "How is
    # this scored?" on both clients. It used to be a "Measures" list of its own
    # beside the methodology cards, which show the same measures in full.
    counted = {id(f) for f in measured}
    measures = [{'id': f.get('exercise_id'), 'name': f.get('name') or f.get('exercise_id'),
                 'status': f.get('status'),
                 'points': STATUS_POINTS.get(f.get('status')) if id(f) in counted else None,
                 'detail': (f.get('change_summary') if id(f) in counted else f.get('waiting_for'))
                           or f.get('change_summary')}
                for f in findings]
    return {'basis': basis, 'summary': summary, 'parts': parts,
            'completed': completed, 'scheduled': scheduled,
            'measured': len(measured), 'waiting': waiting, 'measures': measures}


def _status(score, compliance, completed, scheduled, measured) -> dict:
    """The band and why — the trends first, the sessions as context."""
    b = band(score)
    if completed >= scheduled:
        sessions = 'every session due so far is done'
    else:
        sessions = f'{completed} of {scheduled} sessions due so far are done'
    words = {'ahead': 'ahead', 'on_track': 'on track', 'behind': 'behind', 'stalled': 'stalled'}
    by_status: dict[str, list[str]] = {}
    for f in measured:
        by_status.setdefault(f['status'], []).append(f.get('name') or '')
    # The measures per status, worst first: the clients' Score card shows these
    # as symbols and numbers, and the sentence below says them in words.
    counts = [{'status': st, 'count': len(by_status[st]), 'label': words[st]}
              for st in ('stalled', 'behind', 'on_track', 'ahead') if by_status.get(st)]
    if not measured:
        trends = 'no measure has a trend yet'
    else:
        bits = []
        for c in counts:
            names = by_status[c['status']]
            named = ''
            if c['status'] in ('stalled', 'behind'):
                # Two names, then how many more: "3 stalled (A, B)" read as if
                # the third had no name.
                more = f' and {len(names) - 2} more' if len(names) > 2 else ''
                named = f' ({", ".join(names[:2])}{more})'
            bits.append(f'{c["count"]} {c["label"]}{named}')
        trends = ', '.join(bits)
    reason = f'{trends}; {sessions}.'
    return {'id': b['id'], 'label': b['label'], 'reason': reason[0].upper() + reason[1:], 'bands': BANDS,
            'counts': counts}


def _entry_words(pr: dict) -> dict:
    prim = vocabulary.PRIMITIVES.get(pr.get('primitive') or '') or {}
    needs = [vocabulary.NEEDS[n] for n in prim.get('needs') or [] if n in vocabulary.NEEDS]
    return {
        'description': prim.get('measures'),
        'needs': [{'label': n['label'], 'where': n['where']} for n in needs],
    }


def _describe_findings(findings: list[dict], doc: dict | None) -> None:
    """Each finding says what it measures, and how far it is from a trend."""
    by_id: dict[str, dict] = {}
    for pr in (doc or {}).get('progress') or []:
        by_id[pr['id']] = pr
        for ex in pr.get('exercises') or []:
            if ex.get('exerciseId'):
                by_id.setdefault(ex['exerciseId'], pr)
    for f in findings:
        pr = by_id.get(f.get('exercise_id'))
        if not pr:
            continue
        words = _entry_words(pr)
        f['description'] = words['description']
        if f.get('status') not in STATUS_POINTS:
            points = len(pr.get('series') or [])
            f['waiting_for'] = (f'{points} of 2 sessions logged — the trend starts at 2.'
                                if points < 2 else 'Collecting data — not enough points for a trend yet.')


def _pending(doc: dict | None, today: date) -> list[dict]:
    """Measures of this program's methodology that have no data yet and will
    — the ones that never apply to it (planned 0) are left out."""
    out = []
    for pr in (doc or {}).get('progress') or []:
        has_series = bool(pr.get('series')) or any(ex.get('series') for ex in pr.get('exercises') or [])
        scope = pr.get('programScope') or {}
        if has_series or not scope.get('planned') or pr.get('status') == 'error':
            continue
        words = _entry_words(pr)
        cov = pr.get('coverage') or {}
        if not cov.get('inScope'):
            nxt = scope.get('nextDate')
            reason = (f'None of the sessions it measures has come up yet — the next is {_day(nxt)}.'
                      if nxt else 'None of the sessions it measures has come up yet.')
        else:
            what = ' and '.join(n['label'].lower() for n in words['needs']) or 'the session'
            reason = f'Sessions it measures are done but not logged in detail — log {what}.'
        out.append({'id': pr['id'], 'label': pr.get('label') or pr['id'],
                    'description': words['description'], 'reason': reason, 'needs': words['needs']})
    return out


def _day(iso: str) -> str:
    try:
        d = date.fromisoformat(iso)
    except (TypeError, ValueError):
        return iso
    return d.strftime('%a %-d %b')
