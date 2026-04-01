"""JWT authentication middleware for the Flask API.

Verifies Supabase JWTs using the project's JWKS endpoint (supports both
ES256 new-style and HS256 legacy tokens automatically).

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

_jwks_client: PyJWKClient | None = None
if SUPABASE_URL:
    _jwks_client = PyJWKClient(f'{SUPABASE_URL}/auth/v1/.well-known/jwks.json')


def require_auth(f):
    """Decorator that validates Supabase JWTs and sets g.user_id."""
    @wraps(f)
    def decorated(*args, **kwargs):
        if not _jwks_client:
            # Dev mode: no Supabase URL configured — bypass auth
            g.user_id = 'local-dev-user'
            return f(*args, **kwargs)

        header = request.headers.get('Authorization', '')
        if not header.startswith('Bearer '):
            return jsonify({'detail': 'Missing authorization token'}), 401

        token = header.split(' ', 1)[1]
        try:
            signing_key = _jwks_client.get_signing_key_from_jwt(token)
            payload = pyjwt.decode(
                token,
                signing_key.key,
                algorithms=['ES256', 'RS256', 'HS256'],
                options={'verify_aud': False},
            )
            g.user_id = payload['sub']
        except pyjwt.ExpiredSignatureError:
            return jsonify({'detail': 'Token expired'}), 401
        except pyjwt.InvalidTokenError as e:
            return jsonify({'detail': f'Invalid token: {e}'}), 401
        except Exception as e:
            return jsonify({'detail': f'Auth error: {e}'}), 401

        return f(*args, **kwargs)

    return decorated
