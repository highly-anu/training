"""JWT authentication middleware for the Flask API.

When SUPABASE_JWT_SECRET is set, validates Bearer tokens issued by Supabase Auth.
When it is not set (local dev without Supabase), auth is bypassed and g.user_id
is set to 'local-dev-user' so protected routes still function.
"""
from __future__ import annotations

import os
from functools import wraps

import jwt as pyjwt
from flask import g, jsonify, request

SUPABASE_JWT_SECRET = os.environ.get('SUPABASE_JWT_SECRET', '')


def require_auth(f):
    """Decorator that validates Supabase JWTs and sets g.user_id."""
    @wraps(f)
    def decorated(*args, **kwargs):
        if not SUPABASE_JWT_SECRET:
            # Dev mode: no JWT secret configured — bypass auth
            g.user_id = 'local-dev-user'
            return f(*args, **kwargs)

        header = request.headers.get('Authorization', '')
        if not header.startswith('Bearer '):
            return jsonify({'detail': 'Missing authorization token'}), 401

        token = header.split(' ', 1)[1]
        try:
            payload = pyjwt.decode(
                token,
                SUPABASE_JWT_SECRET,
                algorithms=['HS256'],
                options={'verify_aud': False},  # Supabase sets aud=authenticated
            )
            g.user_id = payload['sub']  # UUID string matching auth.users.id
        except pyjwt.ExpiredSignatureError:
            return jsonify({'detail': 'Token expired'}), 401
        except pyjwt.InvalidTokenError as e:
            return jsonify({'detail': f'Invalid token: {e}'}), 401

        return f(*args, **kwargs)

    return decorated
