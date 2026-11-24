#!/bin/zsh
# Creates a self-signed "Budget Guard Signing" code signing certificate in the login keychain.
# A stable signature lets macOS keep Budget Guard's permissions (notifications, login item) across rebuilds;
# with an ad-hoc signature, every build looks like a new app.
set -euo pipefail

NAME="Budget Guard Signing"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
    exit 0
fi

echo "Creating local code signing certificate \"$NAME\"…"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$tmp/cert.cnf" \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
pass=$(/usr/bin/openssl rand -hex 16)
/usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$NAME" \
    -out "$tmp/cert.p12" -passout "pass:$pass" 2>/dev/null
security import "$tmp/cert.p12" -k ~/Library/Keychains/login.keychain-db -P "$pass" -T /usr/bin/codesign >/dev/null
echo "Certificate created. If macOS asks whether codesign may use it, choose \"Always Allow\"."
