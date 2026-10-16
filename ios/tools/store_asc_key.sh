#!/usr/bin/env bash
# Put the App Store Connect API key into the login Keychain, once, so
# ios/archive.sh can upload to TestFlight without 1Password or anyone at the
# Mac. Run it yourself (it reads 1Password, so approve there):
#
#   ios/tools/store_asc_key.sh
#
# Stored base64 (the .p8 is multi-line, which `security -w` would hex-encode),
# readable without a prompt by /usr/bin/security only. Remove it with
#   security delete-generic-password -s training-asc-api-key
set -euo pipefail
umask 077
KEY_ID="GS974AHJ7N"
ISSUER="3196e516-4057-453d-88f5-9e670dd21141"
OP_DOCUMENT="rc642pznsccd4va35e4f7e23ha"        # "Appstore Connect API key", Private vault

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
op document get "$OP_DOCUMENT" --out-file "$tmp/key.p8" >/dev/null
grep -q "BEGIN PRIVATE KEY" "$tmp/key.p8" || { echo "error: that is not a .p8 key" >&2; exit 1; }

security add-generic-password -U \
    -s training-asc-api-key -a "$KEY_ID" \
    -l "Training Companion — App Store Connect API key" \
    -j "issuer $ISSUER; base64 of AuthKey_$KEY_ID.p8; read by ios/archive.sh" \
    -T /usr/bin/security \
    -w "$(base64 -i "$tmp/key.p8" | tr -d '\n')"

security find-generic-password -s training-asc-api-key -w | base64 -d | cmp -s - "$tmp/key.p8" \
    && echo "Stored key $KEY_ID in the login Keychain; ios/archive.sh will use it."
