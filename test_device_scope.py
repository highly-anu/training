#!/usr/bin/env python
"""A paired watch's device token reaches only the routes the watch calls.

Enumerates every route behind require_auth and sends each a ciqdev_ token: all
but src.auth.DEVICE_ROUTES must answer 403 before the handler runs. A token
used to be accepted everywhere, so one read off a lost watch could rewrite the
program, the profile or revoke the athlete's other devices. Also covers
revoking by the display id the Devices list shows, and the model name a
pairing gets from its part number. No DB:

    .venv/bin/python test_device_scope.py
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

os.environ['SUPABASE_URL'] = ''
os.environ.pop('DATABASE_URL', None)
sys.path.insert(0, str(Path(__file__).parent))

import api  # noqa: E402
from src import auth, device_store  # noqa: E402
from werkzeug.routing import IntegerConverter  # noqa: E402

_failures: list[str] = []


def check(label: str, condition: bool, detail: str = '') -> None:
    if condition:
        print(f'  ok   {label}')
    else:
        print(f'  FAIL {label}' + (f' — {detail}' if detail else ''))
        _failures.append(label)


def protected_routes():
    adapter = api.app.url_map.bind('localhost')
    for rule in api.app.url_map.iter_rules():
        view = api.app.view_functions.get(rule.endpoint)
        if not getattr(view, 'requires_auth', False):
            continue
        values = {a: (1 if isinstance(rule._converters.get(a), IntegerConverter) else 'x')
                  for a in rule.arguments}
        for method in sorted(rule.methods - {'HEAD', 'OPTIONS'}):
            yield method, rule.rule, adapter.build(rule.endpoint, values, method=method)


def test_scope() -> None:
    print('device token scope')
    calls = []
    saved = device_store.user_for_token
    device_store.user_for_token = lambda tok: calls.append(tok) or 'watch-owner'
    client = api.app.test_client()
    headers = {'Authorization': 'Bearer ciqdev_lost-watch-token'}
    routes = list(protected_routes())
    try:
        # Every @require_auth in api.py is one view; a view the walk cannot
        # see (a decorator that drops the marker) would escape the check below.
        decorated = (Path(__file__).parent / 'api.py').read_text(encoding='utf-8').count('\n@require_auth\n')
        views = {api.app.url_map._rules_by_endpoint[e][0].endpoint
                 for e in api.app.view_functions
                 if getattr(api.app.view_functions[e], 'requires_auth', False)}
        check(f'found every protected view ({len(views)} of {decorated})', len(views) == decorated,
              f'{len(views)} vs {decorated}')
        rules = {(m, r) for m, r, _ in routes}
        missing = auth.DEVICE_ROUTES - rules
        check('every allowlisted route exists and is protected', not missing, str(missing))

        leaked = []
        for method, rule, url in routes:
            if (method, rule) in auth.DEVICE_ROUTES:
                continue
            resp = client.open(url, method=method, headers=headers, json={})
            if resp.status_code != 403:
                leaked.append(f'{method} {rule} -> {resp.status_code}')
        check('every other route answers 403 to a device token', not leaked, '; '.join(leaked))
        check('…before the token is even looked up', calls == [], f'{len(calls)} lookups')

        resp = client.delete('/api/devices/ciqdev_abcdefg…', headers=headers)
        check('a device token cannot revoke a device', resp.status_code == 403, str(resp.status_code))
        resp = client.put('/api/user/program', headers=headers, json={'weeks': []})
        check('a device token cannot overwrite the program', resp.status_code == 403, str(resp.status_code))
    finally:
        device_store.user_for_token = saved

    # An unpaired token on an allowlisted route is still 401, not 403 or 200.
    device_store.user_for_token = lambda tok: None
    try:
        resp = api.app.test_client().get('/api/health/readiness', headers=headers)
        check('an unpaired token on a watch route is 401', resp.status_code == 401, str(resp.status_code))
    finally:
        device_store.user_for_token = saved


def test_revoke_resolution() -> None:
    print('revoke by display id')
    a = 'ciqdev_' + 'A' * 43
    b = 'ciqdev_' + 'B' * 43
    owned = [a, b]
    resolve = device_store._resolve_owned
    check('the full token resolves', resolve(a, owned) == a)
    check('the display id resolves', resolve(device_store.display_id(a), owned) == a,
          device_store.display_id(a))
    check('…without its ellipsis too', resolve(a[:device_store.DISPLAY_LEN], owned) == a)
    check('"ciqdev_" alone names nothing', resolve('ciqdev_', owned) is None)
    check('an empty id names nothing', resolve('', owned) is None)
    twin = 'ciqdev_' + 'A' * 7 + 'Z' * 36
    check('a prefix two tokens share names nothing', resolve(device_store.display_id(a), [a, twin]) is None)
    check('another athlete\'s token names nothing', resolve(device_store.display_id(a), [b]) is None)


def test_labels() -> None:
    print('device labels')
    check('the fenix 9 Pro part number is named',
          device_store.device_label('006-B4953-00', 'Garmin watch') == 'fēnix 9 Pro 47 mm')
    check('an unknown part number shows itself',
          device_store.device_label('006-B9999-00', 'Garmin watch') == 'Garmin 006-B9999-00')
    check('an old build with no part number keeps its name',
          device_store.device_label(None, 'Garmin Fenix 9') == 'Garmin Fenix 9')
    check('nothing at all is "Garmin watch"', device_store.device_label(None, None) == 'Garmin watch')


if __name__ == '__main__':
    test_scope()
    test_revoke_resolution()
    test_labels()
    print()
    if _failures:
        print(f'{len(_failures)} FAILED: ' + '; '.join(_failures))
        sys.exit(1)
    print('all passed')
