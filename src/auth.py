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
        try:
            signing_key = _jwks_client.get_signing_key_from_jwt(token)
            return pyjwt.decode(
                token,
                signing_key.key,
                algorithms=['ES256', 'RS256'],
                options={'verify_aud': False},
            )
        except Exception:
            pass

    raise pyjwt.InvalidTokenError('No valid signing key available')


def require_auth(f):
    """Decorator that validates Supabase JWTs and sets g.user_id."""
    @wraps(f)
    def decorated(*args, **kwargs):
        if not SUPABASE_URL:
            # Dev mode: no Supabase URL configured — bypass auth
            g.user_id = 'local-dev-user'
            return f(*args, **kwargs)

        header = request.headers.get('Authorization', '')
        if not header.startswith('Bearer '):
            return jsonify({'detail': 'Missing authorization token'}), 401

        token = header.split(' ', 1)[1]
        try:
            payload = _decode_token(token)
            g.user_id = payload['sub']
        except pyjwt.ExpiredSignatureError:
            return jsonify({'detail': 'Token expired'}), 401
        except pyjwt.InvalidTokenError as e:
            return jsonify({'detail': f'Invalid token: {e}'}), 401
        except Exception as e:
            return jsonify({'detail': f'Auth error: {e}'}), 401

        return f(*args, **kwargs)

    return decorated
