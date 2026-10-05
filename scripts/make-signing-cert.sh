#!/bin/bash
# Creates a private self-signed code-signing certificate ("Mimo Local Signing")
# in your login keychain. build.sh signs with it so every rebuild keeps the same
# identity, and macOS remembers the Screen & System Audio Recording permission
# instead of asking again after each build. Safe to run more than once.
set -euo pipefail
NAME="Mimo Local Signing"

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "Signing certificate \"$NAME\" already exists."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS="$(openssl rand -hex 16)"

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$NAME" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
# -legacy: macOS's keychain can't read OpenSSL 3's default PKCS#12 encryption.
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -passout "pass:$PASS" -out "$TMP/id.p12" 2>/dev/null \
  || openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
       -name "$NAME" -passout "pass:$PASS" -out "$TMP/id.p12"
security import "$TMP/id.p12" -k ~/Library/Keychains/login.keychain-db \
  -P "$PASS" -T /usr/bin/codesign >/dev/null

echo "Created signing certificate \"$NAME\" in your login keychain."
