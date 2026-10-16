"""What GET /api/progression/review says about its own number.

The score was compliance × 0.4 + the mean finding status × 0.6, with a
finding that had no data yet counted as a neutral 50. In week 1 that put an
athlete who had done every session at exactly 70 — the "On Track" line — for
no reason they could see, and one more data point could swing it either way.
Now a finding joins the score only once it measures something; until one
does, the score is compliance alone and says so.

Everything a client shows about the score is built here — the sum, the
status band and why, what the compliance covers, the measures still waiting
for data and how to start them — so the web and the phone cannot word it
differently (the web's widget called the low band "Behind", the phone "Off
Track"). Pure; `test_progression_review.py` runs it on hand-built documents.
"""
from __future__ import annotations

from datetime import date

from src.analytics import vocabulary

COMPLIANCE_WEIGHT = 0.4
TRENDS_WEIGHT = 0.6
STATUS_POINTS = {'ahead': 100, 'on_track': 80, 'behind': 40, 'stalled': 20}

BANDS = [
    {'id': 'on_track', 'label': 'On Track', 'min': 70},
    {'id': 'mixed', 'label': 'Mixed', 'min': 45},
    {'id': 'off_track', 'label': 'Off Track', 'min': 0},
]

PURPOSE = ('Is the training working? Your lifts and skills over time, scored with '
           'how many sessions you have done. The Program tab shows how closely you follow the plan.')


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
    if scheduled == 0:
        score = None
        basis = 'not_started'
    elif measured:
        trends = round(sum(STATUS_POINTS[f['status']] for f in measured) / len(measured))
        score = round(compliance * COMPLIANCE_WEIGHT + trends * TRENDS_WEIGHT)
        basis = 'compliance_and_trends'
    else:
        trends = None
        score = compliance
        basis = 'compliance_only'

    review['overall_score'] = score
    review['score_breakdown'] = _breakdown(basis, compliance, completed, scheduled,
                                           measured, findings, trends if basis != 'not_started' else None)
    review['score_status'] = _status(score, compliance, completed, scheduled, measured) if score is not None else None
    review['scope_label'] = (f'{completed} of {scheduled} session{"" if scheduled == 1 else "s"} so far'
                             f' · week {max(weeks, 1)}') if scheduled else 'No session due yet'
    review['pending_measures'] = _pending(doc, today)
    review['purpose'] = PURPOSE
    # The tracker's "insufficient_data" flag meant "no score"; there is one now.
    if score is not None:
        review['flags'] = [f for f in review.get('flags') or [] if f != 'insufficient_data']
        review['recommendations'] = [r for r in review.get('recommendations') or []
                                     if not r.startswith('Log at least 2 sessions with set data')]
    return review


def _breakdown(basis, compliance, completed, scheduled, measured, findings, trends) -> dict:
    waiting = len(findings) - len(measured)
    if basis == 'compliance_and_trends':
        c_pts = round(compliance * COMPLIANCE_WEIGHT)
        t_pts = round(trends * TRENDS_WEIGHT)
        summary = (f'Sessions {compliance}% × 0.4 = {c_pts} + trends {trends} × 0.6 = {t_pts}'
                   f' (from {len(measured)} measure{"" if len(measured) == 1 else "s"}'
                   + (f'; {waiting} still collecting data' if waiting else '') + ').')
        parts = [
            {'id': 'compliance', 'label': 'Sessions done', 'value': compliance, 'weight': COMPLIANCE_WEIGHT, 'points': c_pts},
            {'id': 'trends', 'label': 'Lift and skill trends', 'value': trends, 'weight': TRENDS_WEIGHT, 'points': t_pts},
        ]
    elif basis == 'compliance_only':
        summary = (f'Sessions only for now: {completed} of {scheduled} done. Trends count once a measure '
                   'has data from 2 sessions.')
        parts = [{'id': 'compliance', 'label': 'Sessions done', 'value': compliance, 'weight': 1.0, 'points': compliance}]
    else:
        summary = 'No session was due yet, so there is nothing to score.'
        parts = []
    return {'basis': basis, 'summary': summary, 'parts': parts,
            'completed': completed, 'scheduled': scheduled,
            'measured': len(measured), 'waiting': waiting}


def _status(score, compliance, completed, scheduled, measured) -> dict:
    b = band(score)
    if completed >= scheduled:
        sessions = 'every session due so far is done'
    else:
        sessions = f'{completed} of {scheduled} sessions due so far are done'
    if not measured:
        trends = 'no lift or skill trend yet'
    else:
        counts: dict[str, list[str]] = {}
        for f in measured:
            counts.setdefault(f['status'], []).append(f.get('name') or '')
        words = {'ahead': 'ahead', 'on_track': 'on track', 'behind': 'behind', 'stalled': 'stalled'}
        bits = []
        for st in ('stalled', 'behind', 'on_track', 'ahead'):
            names = counts.get(st)
            if not names:
                continue
            named = f' ({", ".join(names[:2])})' if st in ('stalled', 'behind') else ''
            bits.append(f'{len(names)} {words[st]}{named}')
        trends = ', '.join(bits)
    reason = f'{sessions}; {trends}.'
    return {'id': b['id'], 'label': b['label'], 'reason': reason[0].upper() + reason[1:], 'bands': BANDS}


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
