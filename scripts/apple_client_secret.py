#!/usr/bin/env python
"""The client secret web Sign in with Apple needs, for Supabase ▸ Auth ▸ Apple.

Apple does not issue a secret: the developer signs one — an ES256 JWT made with
the account's Sign in with Apple key (.p8) — and Apple refuses any that lives
longer than six months. So this runs twice a year; when it lapses, "Continue
with Apple" on the web stops working (the iPhone never uses it). The output
goes into "Secret Key (for OAuth)" in the Apple provider.

The key lives only in 1Password (document "Training web sign in", Key ID on
the item "Appstore sign in with apple API key"); piped in, it never touches
the disk, and the secret goes to the clipboard rather than the terminal:

    op document get 'Training web sign in' | \\
        .venv/bin/python scripts/apple_client_secret.py --key-id YF8QR58W8R --p8 - | tr -d '\\n' | pbcopy
"""
from __future__ import annotations

import argparse
import sys
import time
from datetime import datetime, timezone

import jwt

TEAM_ID = 'HC8NZU8U3U'
SERVICES_ID = 'haerdsoft.TrainingCompanion.web'
# Apple's ceiling is 15 777 000 s (six months); a day short of it.
LIFETIME_SECONDS = 15_777_000 - 86_400


def client_secret(private_key: str, key_id: str, team_id: str = TEAM_ID,
                  client_id: str = SERVICES_ID, now: int | None = None) -> tuple[str, int]:
    """The signed secret and the Unix time it expires."""
    issued = int(time.time()) if now is None else now
    expires = issued + LIFETIME_SECONDS
    token = jwt.encode(
        {'iss': team_id, 'iat': issued, 'exp': expires,
         'aud': 'https://appleid.apple.com', 'sub': client_id},
        private_key,
        algorithm='ES256',
        headers={'kid': key_id},
    )
    return token, expires


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--key-id', required=True, help='the Key ID shown beside the key in Certificates, Identifiers & Profiles ▸ Keys')
    parser.add_argument('--p8', required=True, help="path to the AuthKey_….p8 file, or '-' to read it from stdin")
    parser.add_argument('--team-id', default=TEAM_ID)
    parser.add_argument('--client-id', default=SERVICES_ID, help='the Services ID (not the app bundle id)')
    args = parser.parse_args()

    key = sys.stdin.read() if args.p8 == '-' else open(args.p8, encoding='utf-8').read()
    token, expires = client_secret(key, args.key_id, args.team_id, args.client_id)
    when = datetime.fromtimestamp(expires, timezone.utc).strftime('%Y-%m-%d')
    print(token)
    print(f'\nExpires {when}. Paste the line above into Supabase ▸ Authentication ▸ '
          f'Sign In / Providers ▸ Apple ▸ Secret Key (for OAuth), and renew before then.',
          file=sys.stderr)


if __name__ == '__main__':
    main()
