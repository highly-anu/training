"""The one slot for work that parses every package and generates programs.

The API serves on four threads in a 256 MB machine: two such jobs at once
is what took it past its memory (api.py, "the heavy gate"). A request never
waits for the slot — it answers `busy` and the client tries again
(api._heavy_run). The package builder's worker, which serves no request, may
wait its turn (`slot`).
"""
from __future__ import annotations

import contextlib
import threading

GATE = threading.BoundedSemaphore(1)


class Busy(Exception):
    """The slot was not free within the wait."""


@contextlib.contextmanager
def slot(wait_seconds: float | None = None):
    """Hold the slot for a block. `wait_seconds` None waits as long as it
    takes; a number raises Busy when it is not free in time."""
    got = GATE.acquire() if wait_seconds is None else GATE.acquire(timeout=wait_seconds)
    if not got:
        raise Busy()
    try:
        yield
    finally:
        GATE.release()
