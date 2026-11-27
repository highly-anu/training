#!/usr/bin/env python
"""A key service that does not answer is an outage (503), never a bad token
(401). On 2026-11-27 Supabase restricted the project for its egress quota, its
key endpoint answered 402, and every request of every athlete read 401.

Tokens here are signed with a key made for the test; the key service is a
stand-in that answers, fails to connect, or does not know the kid. No network,
no database.

Run: SUPABASE_URL='' .venv/bin/python test_auth_unavailable.py
"""
from __future__ import annotations

import os
import sys
import time

os.environ['SUPABASE_URL'] = ''
os.environ['DATABASE_URL'] = ''

import jwt as pyjwt  # noqa: E402
from cryptography.hazmat.primitives.asymmetric import ec  # noqa: E402
from jwt.exceptions import PyJWKClientConnectionError, PyJWKClientError  # noqa: E402

import api  # noqa: E402
from src import auth  # noqa: E402

FAILURES: list[str] = []
client = api.app.test_client()
KEY = ec.generate_private_key(ec.SECP256R1())


def check(label: str, condition: bool, detail='') -> None:
    print(f"  {'ok  ' if condition else 'FAIL'} {label}{'' if condition else f' — {detail}'}")
    if not condition:
        FAILURES.append(label)


class Keys:
    """The key service: `mode` is up, down (no connection) or unknown (no such kid)."""
    mode = 'up'

    def get_signing_key_from_jwt(self, token):
        if self.mode == 'down':
            raise PyJWKClientConnectionError('Fail to fetch data from the url, err: "HTTP Error 402"')
        if self.mode == 'unknown':
            raise PyJWKClientError('Unable to find a signing key that matches')
        return type('K', (), {'key': KEY.public_key()})()


def token(kid='k1', exp=3600):
    return pyjwt.encode({'sub': 'athlete-1', 'exp': int(time.time()) + exp}, KEY,
                        algorithm='ES256', headers={'kid': kid})


def get(tok):
    return client.get('/api/profile', headers={'Authorization': f'Bearer {tok}'})


def main() -> int:
    keys = Keys()
    auth.SUPABASE_URL, auth.SUPABASE_JWT_SECRET = 'https://example.test', ''
    auth._jwks_client = keys
    auth._known_keys.clear()

    keys.mode = 'down'
    r = get(token())
    check('key service down, key never seen: 503', r.status_code == 503, r.status_code)
    check('  and it says why', (r.get_json() or {}).get('reason') == 'auth_unavailable', r.get_json())

    keys.mode = 'up'
    r = get(token())
    check('key service up: the token is accepted', r.status_code not in (401, 503), r.status_code)

    keys.mode = 'down'
    r = get(token())
    check('key service down, key seen before: still accepted', r.status_code not in (401, 503), r.status_code)
    r = get(token(kid='k2'))
    check('  another kid is still an outage', r.status_code == 503, r.status_code)

    r = get(token(exp=-60))
    check('an expired token is 401 and says so', r.status_code == 401
          and (r.get_json() or {}).get('detail') == 'Token expired', r.get_json())

    keys.mode = 'unknown'
    r = get(token(kid='k3'))
    check('a kid the service does not know is a bad token: 401', r.status_code == 401, r.status_code)
    r = get('abc.def.ghi')
    check('garbage is 401', r.status_code == 401, r.status_code)

    print(f"\n{len(FAILURES)} failed" if FAILURES else '\nall passed')
    return 1 if FAILURES else 0


if __name__ == '__main__':
    sys.exit(main())
