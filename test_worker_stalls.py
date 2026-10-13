"""The production worker no longer stalls behind one slow client.

Gunicorn runs gthread (Dockerfile), so every thread needs its own database
connection (src/db.py); a send that makes no progress fails after
api._SEND_TIMEOUT_S; large JSON goes out gzipped, except to a watch. No
database: psycopg2.connect is stubbed. Run with SUPABASE_URL=''.
"""
import gzip
import json
import os
import socket
import struct
import sys
import threading

os.environ.setdefault('SUPABASE_URL', '')

import api  # noqa: E402
import src.db  # noqa: E402


def run():
    failures = []

    def check(cond, msg):
        if not cond:
            failures.append(msg)

    client = api.app.test_client()

    # ── gzip ────────────────────────────────────────────────────────────────
    plain = client.get('/api/exercises')
    body = plain.get_data()
    check(len(body) > api._GZIP_MIN_BYTES, f'/exercises is only {len(body)} bytes')
    check('Content-Encoding' not in plain.headers, 'gzipped without Accept-Encoding')

    zipped = client.get('/api/exercises', headers={'Accept-Encoding': 'gzip, deflate, br'})
    check(zipped.headers.get('Content-Encoding') == 'gzip', 'not gzipped when asked')
    raw = zipped.get_data()
    check(int(zipped.headers.get('Content-Length', -1)) == len(raw), 'Content-Length is not the gzipped size')
    check('Accept-Encoding' in zipped.headers.get('Vary', ''), 'no Vary: Accept-Encoding')
    check(json.loads(gzip.decompress(raw)) == json.loads(body), 'gzipped body differs')
    check(len(raw) * 3 < len(body), f'gzip saved little: {len(raw)} of {len(body)}')

    small = client.get('/api/philosophies?nonexistent=1', headers={'Accept-Encoding': 'gzip'})
    if len(small.get_data()) < api._GZIP_MIN_BYTES:
        check('Content-Encoding' not in small.headers, 'a small body was gzipped')

    # A watch's device token is never answered gzipped (it is rejected here,
    # but the decision is the header's, before any route runs).
    with api.app.test_request_context('/api/exercises', headers={
            'Accept-Encoding': 'gzip', 'Authorization': 'Bearer ciqdev_abc'}):
        resp = api.app.response_class(json.dumps({'x': 'y' * 5000}), mimetype='application/json')
        out = api._gzip(resp)
        check('Content-Encoding' not in out.headers, 'a watch request was gzipped')

    # ── the send timeout ───────────────────────────────────────────────────
    a, b = socket.socketpair()
    try:
        with api.app.test_request_context('/api/exercises', environ_base={'gunicorn.socket': a}):
            api._bound_send()
        tv = a.getsockopt(socket.SOL_SOCKET, socket.SO_SNDTIMEO, struct.calcsize('ll'))
        check(struct.unpack('ll', tv)[0] == api._SEND_TIMEOUT_S, f'SO_SNDTIMEO {struct.unpack("ll", tv)}')
        # A peer that never reads: the send fails instead of blocking forever.
        a.setsockopt(socket.SOL_SOCKET, socket.SO_SNDTIMEO, struct.pack('ll', 1, 0))
        try:
            a.sendall(b'x' * (64 << 20))
            failures.append('sendall to a peer that never reads returned')
        except OSError:
            pass
    finally:
        a.close()
        b.close()

    # ── one connection per thread ──────────────────────────────────────────
    class FakeConn:
        made = 0

        def __init__(self):
            FakeConn.made += 1
            self.autocommit = False
            self.closed = False

        def cursor(self):
            conn = self

            class Cur:
                def execute(self, *_):
                    if conn.closed:
                        raise RuntimeError('closed')
            return Cur()

        def close(self):
            self.closed = True

    import psycopg2
    real_connect, real_dsn = psycopg2.connect, src.db._pg_dsn
    psycopg2.connect = lambda dsn: FakeConn()
    src.db._pg_dsn = 'postgresql://stub'
    try:
        src.db.close_conn()
        mine = src.db._get_pg_conn()
        check(mine is src.db._get_pg_conn(), 'one thread got two connections')
        check(mine.autocommit, 'connection is not autocommit')
        theirs = []
        t = threading.Thread(target=lambda: theirs.append(src.db._get_pg_conn()))
        t.start()
        t.join()
        check(theirs and theirs[0] is not mine, 'two threads share a connection')
        mine.closed = True                       # a dropped link reconnects
        check(src.db._get_pg_conn() is not mine, 'a dead connection was handed out')
    finally:
        src.db.close_conn()
        psycopg2.connect, src.db._pg_dsn = real_connect, real_dsn

    for f in failures:
        print('FAIL', f)
    print('ok' if not failures else f'{len(failures)} failure(s)')
    return 0 if not failures else 1


if __name__ == '__main__':
    sys.exit(run())
