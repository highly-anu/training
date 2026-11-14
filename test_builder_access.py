#!/usr/bin/env python
"""Who may use the package builder (docs/roadmap.md 21.1): `PACKAGE_BUILDER`
(off | dev | all), the `dev` role read from the verified token, local dev, and
what `GET /api/methods` tells a client.

A production request is made here by giving the auth module a Supabase URL and
a token decoder that answers the claims a test names — the role is read from
the token the server verified, never from anything the request says about
itself. No database: an athlete's packages are files in a scratch folder.

Run: SUPABASE_URL='' .venv/bin/python test_builder_access.py
"""
from __future__ import annotations

import atexit
import os
import shutil
import sys
import tempfile

os.environ['SUPABASE_URL'] = ''
os.environ['DATABASE_URL'] = ''
os.environ.pop('TRAINING_PACKAGES_DIR', None)
os.environ.pop('PACKAGE_BUILDER', None)
os.environ.pop('ANTHROPIC_API_KEY', None)
BASE = tempfile.mkdtemp(prefix='builder-access-')
atexit.register(shutil.rmtree, BASE, True)
os.environ['TRAINING_USER_PACKAGES_DIR'] = BASE

import api  # noqa: E402
from src import auth, package_store  # noqa: E402

FAILURES: list[str] = []
client = api.app.test_client()


def check(label: str, condition: bool, detail='') -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        FAILURES.append(label)


class production:
    """Requests as production sees them: a Supabase URL, and a bearer token
    whose verified claims are `claims[token]`."""

    def __init__(self, claims: dict):
        self.claims = claims

    def __enter__(self):
        self.saved = (auth.SUPABASE_URL, auth._decode_token, os.environ.get('SUPABASE_URL'))
        auth.SUPABASE_URL = 'https://example.invalid'
        os.environ['SUPABASE_URL'] = 'https://example.invalid'

        def decode(token):
            if token not in self.claims:
                raise auth.pyjwt.InvalidTokenError('unknown token')
            return self.claims[token]
        auth._decode_token = decode
        return self

    def __exit__(self, *exc):
        auth.SUPABASE_URL, auth._decode_token = self.saved[0], self.saved[1]
        os.environ['SUPABASE_URL'] = self.saved[2] or ''


def bearer(token: str) -> dict:
    return {'Authorization': f'Bearer {token}'}


CLAIMS = {
    'dev-token': {'sub': 'user-dev', 'app_metadata': {'roles': ['dev']}},
    'plain-token': {'sub': 'user-plain', 'app_metadata': {'roles': []}},
    'no-metadata': {'sub': 'user-bare'},
    # What a client could try: the role anywhere but where Supabase's admin API writes it.
    'self-styled': {'sub': 'user-sly', 'user_metadata': {'roles': ['dev']}, 'roles': ['dev'], 'role': 'dev'},
    'odd-roles': {'sub': 'user-odd', 'app_metadata': {'roles': 'dev'}},
}


def test_local_dev():
    print('local dev (no Supabase): every request is local-dev-user')
    body = client.get('/api/methods').get_json()
    check('the builder is allowed, and says the model has no key', body['available'] is False
          and body['reason'] == 'no_model_key' and body['methods'] == [] and body['builds'] == [], body)
    check('with its limits', body['limits'] == {'daily': 5, 'remaining': 5, 'kept': package_store.MAX_PACKAGES},
          body['limits'])
    check('the package routes answer', client.get('/api/packages').status_code == 200)
    os.environ['ANTHROPIC_API_KEY'] = 'test-key'
    try:
        check('with a key a build can start', client.get('/api/methods').get_json()['available'] is True)
        os.environ['PACKAGE_BUILDER_DAILY_LIMIT'] = '2'
        check('the daily limit is the server\'s to set', client.get('/api/methods').get_json()['limits']['daily'] == 2)
        os.environ['PACKAGE_BUILDER_DAILY_LIMIT'] = 'many'
        check('and a value that is no number is the default', client.get('/api/methods').get_json()['limits']['daily'] == 5)
    finally:
        os.environ.pop('ANTHROPIC_API_KEY', None)
        os.environ.pop('PACKAGE_BUILDER_DAILY_LIMIT', None)
    os.environ['PACKAGE_BUILDER'] = 'off'
    try:
        body = client.get('/api/methods')
        check('off is off here too: 200, not available, not enabled', body.status_code == 200
              and body.get_json()['available'] is False and body.get_json()['reason'] == 'not_enabled')
        check('and the package routes answer 403 not_enabled', client.get('/api/packages').status_code == 403
              and client.get('/api/packages').get_json()['error'] == 'not_enabled'
              and client.delete('/api/methods/zz_none').status_code == 403)
    finally:
        os.environ.pop('PACKAGE_BUILDER', None)


def test_roles():
    print('production, PACKAGE_BUILDER unset (dev): the role is the verified token\'s')
    os.environ['ANTHROPIC_API_KEY'] = 'test-key'
    try:
        with production(CLAIMS):
            dev = client.get('/api/methods', headers=bearer('dev-token')).get_json()
            check('an account with the dev role may build', dev['available'] is True and dev['reason'] is None, dev)
            check('and reaches the package routes', client.get('/api/packages', headers=bearer('dev-token')).status_code == 200)
            for token in ('plain-token', 'no-metadata', 'self-styled', 'odd-roles'):
                res = client.get('/api/methods', headers=bearer(token))
                body = res.get_json()
                check(f'{token}: 200, not available, nothing listed', res.status_code == 200
                      and body['available'] is False and body['reason'] == 'not_enabled' and body['methods'] == [], body)
                check(f'{token}: the package routes answer 403',
                      client.get('/api/packages', headers=bearer(token)).status_code == 403
                      and client.post('/api/packages', headers=bearer(token), json={'files': {}}).status_code == 403
                      and client.delete('/api/methods/zz', headers=bearer(token)).status_code == 403)
            check('no token is 401 before anything else', client.get('/api/methods').status_code == 401
                  and client.get('/api/packages').status_code == 401)
            check('a token that does not verify is 401', client.get('/api/methods', headers=bearer('forged')).status_code == 401)
            check('a device token is refused on every one of them',
                  all(client.open(path, method=method, headers=bearer('ciqdev_x')).status_code == 403
                      for method, path in (('GET', '/api/methods'), ('DELETE', '/api/methods/zz'),
                                           ('GET', '/api/packages'), ('POST', '/api/packages'))))

            print('production, PACKAGE_BUILDER=all')
            os.environ['PACKAGE_BUILDER'] = 'all'
            check('every signed-in athlete may build',
                  client.get('/api/methods', headers=bearer('plain-token')).get_json()['available'] is True
                  and client.get('/api/packages', headers=bearer('no-metadata')).status_code == 200)
            check('still nobody without a token', client.get('/api/methods').status_code == 401)

            print('production, PACKAGE_BUILDER=off')
            os.environ['PACKAGE_BUILDER'] = 'off'
            check('not even the dev role', client.get('/api/methods', headers=bearer('dev-token')).get_json()['reason'] == 'not_enabled'
                  and client.get('/api/packages', headers=bearer('dev-token')).status_code == 403)

            print('a value that is none of the three')
            os.environ['PACKAGE_BUILDER'] = 'everyone-please'
            check('is read as dev', client.get('/api/methods', headers=bearer('plain-token')).get_json()['reason'] == 'not_enabled'
                  and client.get('/api/methods', headers=bearer('dev-token')).get_json()['available'] is True)
            os.environ.pop('PACKAGE_BUILDER', None)

            print('the developer authoring gate is its own')
            check('the dev role does not open the YAML authoring routes or the Dev Lab\'s',
                  client.get('/api/dev/portability', headers=bearer('dev-token')).status_code == 403
                  and client.post('/api/exercises', headers=bearer('dev-token'), json={}).status_code == 403)
    finally:
        os.environ.pop('ANTHROPIC_API_KEY', None)
        os.environ.pop('PACKAGE_BUILDER', None)


def test_methods():
    print("the athlete's methods")
    import test_private_packages as tpp
    me = 'local-dev-user'
    pkg, files = tpp.package_for(me, 'stones', tpp.SCRATCH)
    check('installed', package_store.install(me, files)['installed'])
    try:
        listed = client.get('/api/methods').get_json()['methods']
        check('listed by its name, with its revision and status', len(listed) == 1 and listed[0]['id'] == pkg
              and listed[0]['name'] == 'Odd-object strength (from scratch)' and listed[0]['revision'] == 1
              and listed[0]['status'] == 'installed' and listed[0]['inUse'] is False, listed)
        from src import db
        real = db.get_user_program
        db.get_user_program = lambda user_id: {'goal': {'primary_sources': [pkg]}}
        try:
            check('in use while the athlete\'s program is built from it',
                  client.get('/api/methods').get_json()['methods'][0]['inUse'] is True)
            held = client.delete(f'/api/methods/{pkg}')
            check('and then it cannot be removed', held.status_code == 409 and held.get_json()['error'] == 'in_use'
                  and 'method' in held.get_json()['detail'], held.get_json())
        finally:
            db.get_user_program = real
        with production(CLAIMS):
            other = client.get('/api/methods', headers=bearer('dev-token')).get_json()
            check('another athlete with the role lists none of it', other['methods'] == [], other['methods'])
            check('and cannot remove it', client.delete(f'/api/methods/{pkg}', headers=bearer('dev-token')).status_code == 404)
        check('removed', client.delete(f'/api/methods/{pkg}').status_code == 200
              and client.get('/api/methods').get_json()['methods'] == [])
        check('a second removal is 404', client.delete(f'/api/methods/{pkg}').status_code == 404)
    finally:
        package_store.remove(me, pkg)


def main() -> int:
    test_local_dev()
    test_roles()
    test_methods()
    if FAILURES:
        print(f'{len(FAILURES)} failed')
        return 1
    print('all passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
