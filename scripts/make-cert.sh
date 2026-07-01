#!/bin/bash
# Creates a self-signed local code-signing identity so AirKwotes keeps a stable
# signature across rebuilds. Without this, the app is ad-hoc signed and every
# rebuild looks like a different app to Keychain, causing repeated access prompts.
#
# One-time setup. Idempotent — safe to re-run.
set -euo pipefail

NAME="${AIRKWOTES_SIGN_IDENTITY:-AirKwotes Local Code Signing}"
LOGIN_KC="$HOME/Library/Keychains/login.keychain-db"

# 1) Already present? Done.
if security find-identity -p codesigning 2>/dev/null | grep -q "$NAME"; then
    echo "Identity '$NAME' is already present. Nothing to do."
    exit 0
fi

echo "Creating self-signed code-signing identity: $NAME"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 2) Self-signed cert with the code-signing extended key usage (required so
#    `security find-identity -p codesigning` and `codesign -s` accept it).
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 \
    -subj "/CN=$NAME" \
    -addext "extendedKeyUsage=codeSigning" \
    -addext "basicConstraints=CA:FALSE" \
    -addext "keyUsage=digitalSignature"

# 3) Package as PKCS12 using legacy algorithms (OpenSSL 3.x defaults break
#    macOS `security import`).
CERT_PW="$(openssl rand -hex 16)"
openssl pkcs12 -export -legacy \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/cert.p12" -name "$NAME" -passout "pass:$CERT_PW"

# 4) Import into the login keychain; pre-authorize codesign to use the key
#    so signing is non-interactive.
security import "$TMP/cert.p12" -k "$LOGIN_KC" -P "$CERT_PW" \
    -T /usr/bin/codesign -T /usr/bin/security

echo
echo "Done. Identity now available:"
security find-identity -p codesigning | grep "$NAME" || true
echo
echo "Next: run 'make bundle' — it will sign with this identity automatically."
