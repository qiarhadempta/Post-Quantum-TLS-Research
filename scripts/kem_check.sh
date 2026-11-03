#!/usr/bin/env bash
set -uo pipefail
: "${OQS_MODULES:?run first: source ~/pqc/env.sh}"
PROV="-provider-path $OQS_MODULES -provider oqsprovider -provider default"
DIR="$HOME/pqc/certs"

openssl s_server -accept 4433 -tls1_3 -cert "$DIR/A/server.crt" -key "$DIR/A/server.key" \
  -groups mlkem512 -sigalgs mldsa44 -quiet $PROV > /dev/null 2>&1 &
pid=$!
sleep 2

echo "--- 1. key_share di trace (client mlkem512) ---"
openssl s_client -connect localhost:4433 -tls1_3 -groups mlkem512 -sigalgs mldsa44 \
  -CAfile "$DIR/A/root.crt" -trace $PROV < /dev/null 2>&1 | grep -i -E "key_share|NamedGroup|group" | head -20

echo "--- 2. tes negatif: client hanya X25519 harus GAGAL ---"
openssl s_client -connect localhost:4433 -tls1_3 -groups X25519 -sigalgs mldsa44 \
  -CAfile "$DIR/A/root.crt" $PROV < /dev/null > /tmp/neg.txt 2>&1
echo "exit code: $?"
grep -i -E "alert|error|no shared|failure" /tmp/neg.txt | head -5
echo "baris Verification: OK ada? -> $(grep -c 'Verification: OK' /tmp/neg.txt)"

kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
