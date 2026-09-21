"""Drains the Garmin webhook queue off the request thread.

Why a queue at all: gunicorn runs a single synchronous worker (see Dockerfile,
`--workers 1`), so any network call made inside the webhook handler blocks every
other request on the machine. Garmin also expects a prompt 200 and will disable
an endpoint that keeps erroring or timing out. So the handler writes the payload
to `garmin_webhook_events` and returns; this drains it.

Why a thread rather than a real queue: the app has no scheduler, no broker and
no cron, and fly.io runs it as a single always-on machine
(`min_machines_running = 1`, `auto_stop_machines = false`). The durable row is
what keeps that honest — if the machine restarts mid-batch the event is still
`pending` and the next webhook, or POST /api/oauth/garmin/drain, picks it up.

There is precedent in this codebase: the async parse jobs at api.py use the same
threading approach. Unlike those, the state here is in Postgres rather than an
in-process dict, so it survives the process.
"""
from __future__ import annotations

import io
import json
import logging
import threading

log = logging.getLogger(__name__)

MAX_ATTEMPTS = 5
# One drain at a time; the lock is what makes _kick() idempotent.
_worker_lock = threading.Lock()
_worker: threading.Thread | None = None


# ---------------------------------------------------------------------------
# Queue

def enqueue(event_type: str, payload: dict) -> int | None:
    """Record a received notification. Returns its row id."""
    from src.db import _get_pg_conn
    conn = _get_pg_conn()
    if conn is None:
        return None
    with conn.cursor() as cur:
        _ensure_table(cur)
        cur.execute(
            'INSERT INTO garmin_webhook_events (event_type, payload) '
            'VALUES (%s, %s::jsonb) RETURNING id',
            (event_type, json.dumps(payload)),
        )
        row = cur.fetchone()
    return row[0] if row else None


_TABLE_READY: bool | None = None


def _ensure_table(cur) -> bool:
    global _TABLE_READY
    if _TABLE_READY is not None:
        return _TABLE_READY
    try:
        cur.execute('''
            CREATE TABLE IF NOT EXISTS garmin_webhook_events (
                id           BIGSERIAL PRIMARY KEY,
                received_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                event_type   TEXT NOT NULL,
                payload      JSONB NOT NULL,
                status       TEXT NOT NULL DEFAULT 'pending',
                attempts     INTEGER NOT NULL DEFAULT 0,
                last_error   TEXT,
                processed_at TIMESTAMPTZ
            )
        ''')
        _TABLE_READY = True
    except Exception:
        _TABLE_READY = False
    return _TABLE_READY


def _claim_next() -> dict | None:
    """Take the oldest retryable event. SKIP LOCKED so two drains can't collide."""
    import psycopg2.extras as _extras
    from src.db import _get_pg_conn
    conn = _get_pg_conn()
    if conn is None:
        return None
    with conn.cursor(cursor_factory=_extras.RealDictCursor) as cur:
        if not _ensure_table(cur):
            return None
        cur.execute(f'''
            UPDATE garmin_webhook_events SET status = 'processing', attempts = attempts + 1
            WHERE id = (
                SELECT id FROM garmin_webhook_events
                WHERE status IN ('pending', 'failed') AND attempts < {MAX_ATTEMPTS}
                ORDER BY received_at
                FOR UPDATE SKIP LOCKED
                LIMIT 1
            )
            RETURNING id, event_type, payload, attempts
        ''')
        row = cur.fetchone()
    return dict(row) if row else None


def _finish(event_id: int, status: str, error: str | None = None) -> None:
    from src.db import _get_pg_conn
    conn = _get_pg_conn()
    if conn is None:
        return
    try:
        with conn.cursor() as cur:
            cur.execute(
                'UPDATE garmin_webhook_events '
                'SET status = %s, last_error = %s, processed_at = NOW() WHERE id = %s',
                (status, (error or '')[:2000] or None, event_id),
            )
    except Exception:
        log.exception('could not mark garmin event %s as %s', event_id, status)


# ---------------------------------------------------------------------------
# Processing

def process_activity_notification(notification: dict) -> dict:
    """Import one activity from a ping.

    Returns {'status': 'imported'|'skipped'|'ignored', ...}. Raises only on
    failures worth retrying — a permanent condition (unknown athlete, import
    switched off) is an 'ignored' result, not an exception, so the event stops
    rather than burning through its attempts.
    """
    from src import fit_import, garmin_connect, health_store, workout_matcher

    garmin_user_id = notification.get('userId')
    summary_id = str(notification.get('summaryId') or '')
    if not garmin_user_id:
        return {'status': 'ignored', 'reason': 'no userId in notification'}

    user_id = garmin_connect.user_for_garmin_id(garmin_user_id)
    if not user_id:
        # Someone else's athlete, or a stale registration. Not an error.
        return {'status': 'ignored', 'reason': 'unknown garmin user'}

    if summary_id and garmin_connect.already_imported(garmin_user_id, summary_id):
        return {'status': 'skipped', 'reason': 'already imported'}

    # Enforced here, not only in the UI — otherwise switching auto-import off
    # would do nothing about traffic Garmin is already pushing.
    import api
    if not api.integration_allows(user_id, 'garmin'):
        return {'status': 'ignored', 'reason': 'auto-import disabled for this athlete'}

    workouts: list[dict] = []
    callback_url = notification.get('callbackURL') or notification.get('callbackUrl')
    if callback_url:
        if not garmin_connect.is_allowed_callback(callback_url):
            # A callback pointing outside GARMIN_API_BASE means this ping did
            # not come from Garmin. Drop the whole notification rather than
            # falling back to its summary — trusting the body of a message we
            # have just decided is forged would defeat the point of the check.
            log.warning('refusing garmin notification %s: callback %r is outside %s',
                        summary_id, callback_url, garmin_connect.API_BASE)
            return {'status': 'ignored', 'reason': 'callback URL outside the Garmin API'}

        data = garmin_connect.fetch_activity_bytes(user_id, callback_url)
        try:
            workouts = fit_import.parse_fit(io.BytesIO(data), source='garmin')
        except Exception as e:
            # A real Garmin response that isn't a FIT file — use the summary.
            log.warning('garmin activity %s did not parse as FIT (%s); '
                        'falling back to the summary', summary_id, e)

    if not workouts:
        fallback = garmin_connect.summary_to_workout(notification)
        if fallback:
            workouts = [fallback]

    if not workouts:
        return {'status': 'ignored', 'reason': 'nothing importable in notification'}

    # raise_on_error: a silently failed write here would lose the activity with
    # nothing left to retry from.
    health_store.upsert_workouts(user_id, workouts, raise_on_error=True)
    matched = workout_matcher.match_and_store(user_id, workouts)

    if summary_id:
        garmin_connect.record_import(garmin_user_id, summary_id, user_id, workouts[0]['id'])
    garmin_connect._touch(user_id, 'last_webhook_at')

    return {
        'status': 'imported',
        'workoutId': workouts[0]['id'],
        'confirmedMatches': matched['confirmed'],
        'suggestedMatches': matched['suggested'],
    }


def process_deregistration(notification: dict) -> dict:
    """Garmin telling us the athlete revoked access at their end."""
    from src import garmin_connect
    from src.db import _get_pg_conn

    garmin_user_id = notification.get('userId')
    if not garmin_user_id:
        return {'status': 'ignored', 'reason': 'no userId'}
    user_id = garmin_connect.user_for_garmin_id(garmin_user_id)
    if not user_id:
        return {'status': 'ignored', 'reason': 'unknown garmin user'}

    conn = _get_pg_conn()
    if conn is not None:
        with conn.cursor() as cur:
            cur.execute('DELETE FROM garmin_tokens WHERE user_id = %s', (user_id,))
    return {'status': 'imported', 'reason': 'tokens removed'}


def process_event(event: dict) -> dict:
    """Fan one queued event out to its per-notification handlers."""
    payload = event['payload']
    if isinstance(payload, str):
        payload = json.loads(payload)

    event_type = event['event_type']
    if event_type == 'deregistration':
        items = payload.get('deregistrations') or []
        handler = process_deregistration
    elif event_type == 'permission_change':
        # Nothing to do beyond noting it; the next fetch will fail loudly if
        # the athlete withdrew the activity scope.
        return {'status': 'ignored', 'reason': 'permission change noted'}
    else:
        items = (payload.get('activities')
                 or payload.get('activityDetails')
                 or payload.get('activityFiles')
                 or [])
        handler = process_activity_notification

    if not items:
        return {'status': 'ignored', 'reason': 'no notifications in payload'}

    results = [handler(item) for item in items]
    imported = sum(1 for r in results if r['status'] == 'imported')
    return {'status': 'imported' if imported else 'ignored',
            'processed': len(results), 'imported': imported, 'results': results}


# ---------------------------------------------------------------------------
# Draining

def drain(max_events: int = 50) -> dict:
    """Process queued events until there are none left. Safe to call anywhere."""
    processed = 0
    imported = 0
    failed = 0

    for _ in range(max_events):
        event = _claim_next()
        if event is None:
            break
        processed += 1
        try:
            result = process_event(event)
            _finish(event['id'], 'done' if result['status'] == 'imported' else 'ignored')
            imported += result.get('imported', 0)
        except Exception as e:
            log.exception('garmin event %s failed', event['id'])
            failed += 1
            # Past the attempt cap it parks as 'failed' and stops being claimed.
            _finish(event['id'], 'failed', str(e))

    return {'processed': processed, 'imported': imported, 'failed': failed}


def _run() -> None:
    global _worker
    try:
        drain()
    finally:
        with _worker_lock:
            _worker = None


def kick() -> None:
    """Start a drain in the background if one isn't already running."""
    global _worker
    with _worker_lock:
        if _worker is not None and _worker.is_alive():
            return
        _worker = threading.Thread(target=_run, name='garmin-webhook-worker', daemon=True)
        _worker.start()
