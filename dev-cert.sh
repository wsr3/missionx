#!/bin/bash
# Creates a self-signed code-signing identity in the login keychain.
#
# Why: accessibility (TCC) permission is remembered per code-signing identity.
# Ad-hoc signatures change their hash on every rebuild, so the permission would
# be revoked every time we recompile. A stable self-signed identity keeps it.
#
# Safe to re-run; it skips work that is already done.
set -euo pipefail

IDENTITY_NAME="MissionX Dev"
WORK_DIR="$(cd "$(dirname "$0")" && pwd)/.certs"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# Apple's keychain cannot import PKCS#12 files produced by OpenSSL 3 defaults,
# and it dislikes empty passwords, so use the system LibreSSL and a real one.
OPENSSL="/usr/bin/openssl"
P12_PASS="missionx-dev"

if security find-identity -v -p codesigning | grep -q "$IDENTITY_NAME"; then
    echo "==> Identity '$IDENTITY_NAME' already present"
    security find-identity -v -p codesigning | grep "$IDENTITY_NAME"
    exit 0
fi

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "==> Generating self-signed code-signing certificate"
cat > openssl.cnf <<'CONF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no

[dn]
CN = MissionX Dev

[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes \
    -keyout key.pem -out cert.pem -days 3650 -config openssl.cnf

"$OPENSSL" pkcs12 -export -inkey key.pem -in cert.pem -out identity.p12 \
    -name "$IDENTITY_NAME" -passout "pass:$P12_PASS"

echo "==> Importing into login keychain"
security import identity.p12 -k "$KEYCHAIN" -P "$P12_PASS" -A -T /usr/bin/codesign

echo "==> Trusting it for code signing"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" cert.pem

echo "==> Result"
security find-identity -v -p codesigning | grep "$IDENTITY_NAME" \
    || { echo "FAILED: identity not usable for code signing"; exit 1; }
