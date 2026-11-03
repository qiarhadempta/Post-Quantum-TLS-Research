#!/usr/bin/env bash
set -uo pipefail
: "${OQS_MODULES:?run first: source ~/pqc/env.sh}"
PROV="-provider-path $OQS_MODULES -provider oqsprovider -provider default"
DIR="$HOME/pqc/certs"
mkdir -p "$HOME/pqc/logs"

run() {
  local name=$1 dir=$2 group=$3 sig=$4 port=$5
  echo "=== Scenario $name: group=$group sigalg=$sig ==="
  openssl s_server -accept "$port" -tls1_3 -cert "$DIR/$dir/server.crt" -key "$DIR/$dir/server.key" \
    -groups "$group" -sigalgs "$sig" -quiet $PROV > "$HOME/pqc/logs/server_$name.log" 2>&1 &
  local pid=$!
  sleep 2
  openssl s_client -connect "localhost:$port" -tls1_3 -groups "$group" -sigalgs "$sig" \
    -CAfile "$DIR/$dir/root.crt" -verify_return_error -brief $PROV < /dev/null 2>&1
  echo "(s_client exit code: $?)"
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  echo
}

run A A mlkem512 mldsa44 4433
run B B mlkem512 slhdsasha2128f 4434
run C C X25519 rsa_pss_rsae_sha256 4435
