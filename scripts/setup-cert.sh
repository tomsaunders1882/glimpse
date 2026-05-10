#!/usr/bin/env bash
# Creates a self-signed code signing identity in the user's login keychain
# so Glimpse can be re-signed on every rebuild with a stable signature.
# Stable signature -> Keychain ACL persists -> no password prompt loop.

set -euo pipefail

CERT_NAME="Glimpse Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "\"$CERT_NAME\""; then
    echo "Identity '$CERT_NAME' already exists. Nothing to do."
    exit 0
fi

OPENSSL_BIN="$(command -v openssl)"
if [ -z "$OPENSSL_BIN" ]; then
    echo "ERROR: openssl not found." >&2
    exit 1
fi
OPENSSL_VERSION="$($OPENSSL_BIN version)"
echo "Using $OPENSSL_VERSION"

P12_LEGACY=""
if echo "$OPENSSL_VERSION" | grep -q "OpenSSL 3"; then
    P12_LEGACY="-legacy"
fi

WORK="$(mktemp -d)"
trap "rm -rf $WORK" EXIT
KEY="$WORK/key.pem"
CERT="$WORK/cert.pem"
P12="$WORK/bundle.p12"
PASS="glimpse-temp"

echo "Generating self-signed code signing certificate..."
"$OPENSSL_BIN" req -x509 -newkey rsa:2048 -nodes \
    -keyout "$KEY" -out "$CERT" \
    -days 3650 -subj "/CN=$CERT_NAME/O=Glimpse" \
    -addext "extendedKeyUsage=codeSigning" \
    -addext "keyUsage=digitalSignature" \
    -addext "basicConstraints=CA:false" >/dev/null 2>&1

echo "Bundling key + cert into PKCS12..."
"$OPENSSL_BIN" pkcs12 -export $P12_LEGACY \
    -inkey "$KEY" -in "$CERT" \
    -out "$P12" -passout pass:"$PASS" -name "$CERT_NAME" >/dev/null 2>&1

echo "Importing into login keychain..."
security import "$P12" \
    -k "$KEYCHAIN" -P "$PASS" \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null

echo "Trusting for code signing (you may be prompted for your password)..."
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$CERT"

if security find-identity -v -p codesigning | grep -q "\"$CERT_NAME\""; then
    echo
    echo "Done. '$CERT_NAME' is now a valid code signing identity."
    echo "Run 'make run' to build and launch Glimpse."
else
    echo "ERROR: import succeeded but '$CERT_NAME' is not listed as a valid identity." >&2
    exit 1
fi
