"""JWT authentication middleware for the Flask API.

Verifies Supabase JWTs. Tries JWKS first (RS256/ES256); falls back to the
SUPABASE_JWT_SECRET for HS256 tokens (default for most Supabase projects).

When SUPABASE_URL is not set (local dev without Supabase), auth is bypassed
and g.user_id is set to 'local-dev-user' so protected routes still function.
"""
from __future__ import annotations

import os
from functools import wraps

import jwt as pyjwt
from jwt import PyJWKClient
from jwt.exceptions import PyJWKClientConnectionError, PyJWKClientError
from flask import g, jsonify, request

SUPABASE_URL = os.environ.get('SUPABASE_URL', '')
SUPABASE_JWT_SECRET = os.environ.get('SUPABASE_JWT_SECRET', '')

_jwks_client: PyJWKClient | None = None
if SUPABASE_URL:
    _jwks_client = PyJWKClient(f'{SUPABASE_URL}/auth/v1/.well-known/jwks.json')


def _decode_token(token: str):
    """Try HS256 with JWT secret first, fall back to JWKS for asymmetric tokens."""
    # Try HS256 with the JWT secret (default for most Supabase projects)
    if SUPABASE_JWT_SECRET:
        try:
            return pyjwt.decode(
                token,
                SUPABASE_JWT_SECRET,
                algorithms=['HS256'],
                options={'verify_aud': False},
            )
        except (pyjwt.InvalidSignatureError, pyjwt.InvalidAlgorithmError):
            pass  # Not HS256 — try JWKS

    # Fall back to asymmetric (RS256/ES256) via JWKS
    if _jwks_client:
        return pyjwt.decode(
            token,
            _signing_key(token),
            algorithms=['ES256', 'RS256'],
            options={'verify_aud': False},
        )

    raise pyjwt.InvalidTokenError('No valid signing key available')


class AuthUnavailable(Exception):
    """The token could not be checked because the key service did not answer
    — an outage of ours, not a bad token."""


# kid → key, every key this process has verified with. PyJWKClient keeps its
# own copy for five minutes only; signing keys change rarely, so a key service
# that stops answering must not turn every signed-in athlete away.
_known_keys: dict = {}


def _signing_key(token: str):
    """The key that signed `token`. When the key service cannot be reached:
    the key last seen for its kid, else `AuthUnavailable` — never "invalid
    token", which tells a client to sign in again (it cannot, the same
    service signs in). On 2026-11-27 the Supabase project was restricted for
    its egress quota, the key endpoint answered 402, and every request of
    every athlete read 401."""
    try:
        kid = pyjwt.get_unverified_header(token).get('kid')
    except pyjwt.PyJWTError as e:
        raise pyjwt.InvalidTokenError(str(e))
    try:
        key = _jwks_client.get_signing_key_from_jwt(token).key
    except PyJWKClientConnectionError as e:
        if kid in _known_keys:
            return _known_keys[kid]
        raise AuthUnavailable(str(e))
    except PyJWKClientError as e:
        raise pyjwt.InvalidTokenError(str(e))
    if kid:
        _known_keys[kid] = key
    return key


# The routes a paired watch may call with its ciqdev_ token, as (method, rule).
# A device token used to be accepted on every authenticated route, so one read
# off a lost watch could rewrite the program, the profile or the other paired
# devices. Everything else answers 403 to a device token;
# test_device_scope.py enumerates every protected route against this list.
DEVICE_ROUTES = frozenset({
    ('GET',  '/api/user/today-session'),
    ('GET',  '/api/health/readiness'),
    ('POST', '/api/health/workouts'),
    ('PUT',  '/api/health/sessions/<path:session_key>'),
    ('POST', '/api/health/wellness'),
})


def optional_user_id() -> str | None:
    """Who is asking, on a route that needs no sign-in: the user of a valid
    bearer token, else None — never an error. The reference routes answer
    everyone, and an athlete with packages of their own gets theirs added
    (api.static_json)."""
    header = request.headers.get('Authorization', '')
    token = header.split(' ', 1)[1] if header.startswith('Bearer ') else ''
    from src import device_store
    if token.startswith(device_store.TOKEN_PREFIX):
        return None
    if not SUPABASE_URL:
        return 'local-dev-user'
    if not token:
        return None
    try:
        return _decode_token(token)['sub']
    except Exception:
        return None


def has_role(role: str) -> bool:
    """Whether the signed-in user's verified token carries `role` in
    `app_metadata.roles` — set with Supabase's admin API and the service-role
    key (a user cannot write app_metadata), in force from their next token
    refresh. The web reads the same claim to show the Dev Lab
    (lib/featureFlags.ts); this is the server's reading of it. False for a
    device token and in local dev, which have no claims."""
    claims = getattr(g, 'claims', None) or {}
    roles = (claims.get('app_metadata') or {}).get('roles') or []
    return isinstance(roles, list) and role in roles


def _as_user(f, *args, **kwargs):
    """Run a view as the signed-in athlete: the loader sees their own packages
    beside the shipped ones (src/package_store.py, loader.overlay) for the
    length of the call. The overlay is named only if a loader asks — most
    requests read no package — and always reset: the thread serves someone
    else next."""
    from src import loader, package_store
    user_id = g.user_id
    token = loader.set_overlay(lambda: package_store.overlay_for(user_id))
    try:
        return f(*args, **kwargs)
    finally:
        loader.reset_overlay(token)


def require_auth(f):
    """Decorator that validates Supabase JWTs (or watch device tokens) and sets g.user_id."""
    @wraps(f)
    def decorated(*args, **kwargs):
        header = request.headers.get('Authorization', '')
        token = header.split(' ', 1)[1] if header.startswith('Bearer ') else ''

        # Device-token path (watch companions). Checked first so it works in both
        # dev and prod; a claimed token resolves to its bound user_id.
        from src import device_store
        if token.startswith(device_store.TOKEN_PREFIX):
            rule = request.url_rule.rule if request.url_rule else ''
            if (request.method, rule) not in DEVICE_ROUTES:
                return jsonify({'detail': 'Not available to a device token'}), 403
            user_id = device_store.user_for_token(token)
            if user_id:
                g.user_id = user_id
                g.claims = {}   # a device token carries no claims, so no role
                return _as_user(f, *args, **kwargs)
            return jsonify({'detail': 'Invalid or unpaired device token'}), 401

        if not SUPABASE_URL:
            # Dev mode: no Supabase URL configured — bypass auth
            g.user_id = 'local-dev-user'
            g.claims = {}
            return _as_user(f, *args, **kwargs)

        if not header.startswith('Bearer '):
            return jsonify({'detail': 'Missing authorization token'}), 401

        try:
            payload = _decode_token(token)
            g.user_id = payload['sub']
            # Kept for the request: a role is read from the verified token
            # (has_role), never from anything the client says about itself.
            g.claims = payload
        except AuthUnavailable as e:
            # 503, never 401: nothing is wrong with the athlete's sign-in.
            print(f'[auth] key service unavailable: {e}', flush=True)
            return jsonify({'detail': 'Sign-in cannot be checked right now. Try again shortly.',
                            'reason': 'auth_unavailable'}), 503
        except pyjwt.ExpiredSignatureError:
            return jsonify({'detail': 'Token expired'}), 401
        except pyjwt.InvalidTokenError as e:
            return jsonify({'detail': f'Invalid token: {e}'}), 401
        except Exception as e:
            return jsonify({'detail': f'Auth error: {e}'}), 401

        return _as_user(f, *args, **kwargs)

    decorated.requires_auth = True
    return decorated
