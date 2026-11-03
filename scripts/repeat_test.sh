#!/usr/bin/env bash
set -uo pipefail
: "${OQS_MODULES:?run first: source ~/pqc/env.sh}"
PROV="-provider-path $OQS_MODULES -provider oqsprovider -provider default"
DIR="$HOME/pqc/certs"
N=${1:-20}

repeat() {
  local name=$1 group=$2 sig=$3 port=$4
  openssl s_server -accept "$port" -tls1_3 -cert "$DIR/$name/server.crt" -key "$DIR/$name/server.key" \
    -groups "$group" -sigalgs "$sig" -quiet $PROV > /dev/null 2>&1 &
  local pid=$!
  sleep 2
  local ok=0 dn=0 i out rc
  for i in $(seq 1 "$N"); do
    out=$(openssl s_client -connect "localhost:$port" -tls1_3 -groups "$group" -sigalgs "$sig" \
      -CAfile "$DIR/$name/root.crt" -verify_return_error -brief $PROV < /dev/null 2>&1)
    rc=$?
    if [ "$rc" -eq 0 ]; then ok=$((ok+1)); fi
    case "$out" in *DONE*) dn=$((dn+1)) ;; esac
  done
  echo "Scenario $name: exit0=$ok/$N  DONE=$dn/$N"
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
}

repeat A mlkem512 mldsa44 4433
repeat B mlkem512 slhdsasha2128f 4434
repeat C X25519 rsa_pss_rsae_sha256 4435
