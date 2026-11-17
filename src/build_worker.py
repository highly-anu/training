"""The worker that runs builds of athletes' own methods (docs/roadmap.md 21.2).

One thread per process. It claims a build (src/build_store.py), hands a
`Session` to the builder — the model loop (src/package_builder.py), or a
scripted one in tests — and when the builder returns a package that passed
every gate, installs it for the athlete and writes the result. It serves no
request, so it names the athlete's own packages for itself (loader.overlay),
and it takes the process's one heavy slot only around each gate check, never
while the model is thinking: program previews keep answering meanwhile.

A build that the process dies under is not lost: its draft and transcript
were saved after every turn, its heartbeat goes stale, and the next worker —
this process after a restart (`kick` at startup) or another — claims it and
the builder resumes from what was saved.
"""
from __future__ import annotations

import logging
import threading

from src import build_store, heavy, loader, package_store

_log = logging.getLogger(__name__)

_worker: threading.Thread | None = None
_worker_lock = threading.Lock()

# The builder: Session → {'ok': True, 'files', 'name', 'summary', 'check'} or
# {'ok': False, 'error': {'code', 'message'}}. Set by src/package_builder.py
# when it is imported (api.py does); tests set a scripted one.
BUILDER = None


class Cancelled(Exception):
    """The athlete cancelled the build."""


class Session:
    """What a builder works with: the build's request, its draft and
    transcript as last saved, and the three things it may do — save, ask
    whether to stop, and check the draft against every gate."""

    def __init__(self, row: dict):
        self.id = row['id']
        self.user_id = row['user_id']
        self.request = row.get('request') or {}
        self.draft_files: dict = dict(row.get('draft_files') or {})
        self.transcript: list = list(row.get('transcript') or [])
        self.progress: dict = dict(row.get('progress') or {})
        self.usage: dict = dict(row.get('usage') or {})
        self.attempt = row.get('attempts') or 1
        self.prefix = package_store.owner_prefix(self.user_id)

    def save(self, **progress) -> None:
        """Write the draft, the transcript and the usage as they stand, with
        any progress fields given, and stop here if the athlete cancelled."""
        self.progress.update(progress)
        build_store.save(self.id, progress=self.progress, draft_files=self.draft_files,
                         transcript=self.transcript, usage=self.usage)
        self.stop_if_cancelled()

    def beat(self) -> None:
        """A sign of life during a long model turn (nothing else changed)."""
        build_store.save(self.id)

    def stop_if_cancelled(self) -> None:
        if build_store.cancel_requested(self.id):
            raise Cancelled()

    def check(self, smoke: bool = True, probe=None) -> dict:
        """Every gate on the draft as this athlete's package, with their other
        packages beside it (package_store.check), holding the heavy slot for
        the length of the check. `probe`: package_store.check's."""
        with heavy.slot():
            return package_store.check(self.user_id, self.draft_files, smoke=smoke, probe=probe)


def run_build(row: dict) -> None:
    """One claimed build, to its end."""
    session = Session(row)
    builder = BUILDER
    try:
        if builder is None:
            raise RuntimeError('no builder is configured')
        with loader.overlay(lambda: package_store.overlay_for(session.user_id)):
            outcome = builder(session)
            if not outcome.get('ok'):
                build_store.finish(session.id, 'failed', error=outcome.get('error')
                                   or {'code': 'failed', 'message': 'The method could not be built.'})
                return
            session.draft_files = dict(outcome['files'])
            session.save(stage='installing')
            installed = package_store.install(session.user_id, session.draft_files, checked=outcome.get('check'))
        if not installed.get('installed'):
            build_store.finish(session.id, 'failed', error={
                'code': 'not_installable', 'message': 'The method was written but did not pass the checks.',
                'problems': (installed.get('problems') or [])[:10]})
            return
        build_store.finish(session.id, 'done', progress={**session.progress, 'stage': 'done'}, result={
            'packageId': installed['package'], 'revision': installed['revision'],
            'name': outcome.get('name') or installed['package'], 'summary': outcome.get('summary') or ''})
    except Cancelled:
        build_store.finish(session.id, 'cancelled', error={'code': 'cancelled', 'message': 'Cancelled.'})
    except Exception as e:   # a build that raises is a failed build, never a dead worker
        _log.exception('build %s failed', session.id)
        try:
            build_store.finish(session.id, 'failed', error={
                'code': 'error', 'message': 'Something went wrong while building. Try again.',
                'detail': f'{type(e).__name__}: {e}'[:300]})
        except build_store.StoreError:
            pass


def drain(max_builds: int = 20) -> int:
    """Run builds until none is waiting; how many were run."""
    done = 0
    while done < max_builds:
        try:
            row = build_store.claim_next()
        except build_store.StoreError as e:
            _log.warning('%s', e)
            return done
        if row is None:
            return done
        run_build(row)
        done += 1
    return done


def _run() -> None:
    try:
        drain()
    finally:
        from src import db
        db.close_conn()


def kick() -> None:
    """Start the worker unless one is running (after a build is queued, and
    once at startup if any build was left open)."""
    global _worker
    with _worker_lock:
        if _worker is not None and _worker.is_alive():
            return
        _worker = threading.Thread(target=_run, name='package-build-worker', daemon=True)
        _worker.start()


def join(timeout: float | None = None) -> None:
    """Wait for the worker to finish what it has (tests)."""
    worker = _worker
    if worker is not None:
        worker.join(timeout)
