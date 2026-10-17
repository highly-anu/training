#!/usr/bin/env python
"""The web Sign in with Apple client secret (`scripts/apple_client_secret.py`):
the claims Apple checks, the key id in the header, a lifetime inside Apple's
six-month ceiling, and a signature the key's public half verifies. No network:

    .venv/bin/python test_apple_client_secret.py
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / 'scripts'))

import jwt  # noqa: E402
from cryptography.hazmat.primitives import serialization  # noqa: E402
from cryptography.hazmat.primitives.asymmetric import ec  # noqa: E402

import apple_client_secret as acs  # noqa: E402

_failures: list[str] = []


def check(label: str, condition: bool, detail: str = '') -> None:
    if condition:
        print(f'  ok   {label}')
    else:
        print(f'  FAIL {label}' + (f' — {detail}' if detail else ''))
        _failures.append(label)


def main() -> None:
    print('client secret')
    # A throwaway P-256 key in the PKCS#8 PEM form Apple's .p8 files use.
    key = ec.generate_private_key(ec.SECP256R1())
    pem = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                            serialization.NoEncryption()).decode()
    token, expires = acs.client_secret(pem, 'KEY1234567', now=1_800_000_000)

    header = jwt.get_unverified_header(token)
    check('ES256 with the key id', header.get('alg') == 'ES256' and header.get('kid') == 'KEY1234567', str(header))
    claims = jwt.decode(token, key.public_key(), algorithms=['ES256'],
                        audience='https://appleid.apple.com', options={'verify_exp': False, 'verify_iat': False})
    check('issued by the team', claims['iss'] == 'HC8NZU8U3U', claims['iss'])
    check('for the Services ID, not the bundle id', claims['sub'] == 'haerdsoft.TrainingCompanion.web', claims['sub'])
    check("Apple's audience", claims['aud'] == 'https://appleid.apple.com')
    life = claims['exp'] - claims['iat']
    check('inside the six-month ceiling', 0 < life <= 15_777_000, str(life))
    check('expiry reported as signed', expires == claims['exp'])

    print()
    if _failures:
        print(f'{len(_failures)} FAILED: ' + '; '.join(_failures))
        sys.exit(1)
    print('all passed')


if __name__ == '__main__':
    main()
