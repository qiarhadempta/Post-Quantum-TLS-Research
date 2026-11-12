#!/usr/bin/env bash
set -uo pipefail
: "${PQC_HOME:?}"
: "${OQS_MODULES:?}"
RTT=${1:?RTT_ms}
LOSS=${2:?loss_pct}
N=${3:?N}
W=${4:-5}
D=${5:-10000}
TAG=${6:-test}
PROV="-provider-path $OQS_MODULES -provider oqsprovider -provider default"
DIR="$PQC_HOME/certs"
BENCH="$PQC_HOME/scripts/tlsbench"
OUT="$PQC_HOME/results/$TAG"
mkdir -p "$OUT"
CSV="$OUT/rtt${RTT}_loss${LOSS}.csv"
[ -x "$BENCH" ] || { echo "tlsbench belum dikompilasi: $BENCH"; exit 1; }

bash "$PQC_HOME/scripts/ns_setup.sh" "$RTT" "$LOSS"
for ns in ns_c ns_s; do
  ip netns exec "$ns" sysctl -qw net.ipv4.tcp_no_metrics_save=1 2>/dev/null || true
  ip netns exec "$ns" ip tcp_metrics flush 2>/dev/null || true
done

run() {
  local name=$1 group=$2 sig=$3 port=$4
  ip netns exec ns_s openssl s_server -accept "$port" -tls1_3 \
    -cert "$DIR/$name/server.crt" -key "$DIR/$name/server.key" \
    -groups "$group" -sigalgs "$sig" -num_tickets 0 -no_cache -quiet $PROV >/dev/null 2>&1 &
  local spid=$!
  sleep 2
  ip netns exec ns_c "$BENCH" -a 10.0.0.2 -p "$port" -g "$group" -s "$sig" \
    -c "$DIR/$name/root.crt" -n "$N" -w "$W" -d "$D" -l "$name" -r "$RTT" -L "$LOSS" \
    -o "$CSV" -m "$OQS_MODULES"
  kill "$spid" 2>/dev/null
  wait "$spid" 2>/dev/null
}

run A mlkem512 mldsa44 4433
run B mlkem512 slhdsasha2128f 4434
run C X25519 rsa_pss_rsae_sha256 4435

chown -R "${SUDO_UID:-0}:${SUDO_GID:-0}" "$PQC_HOME/results" 2>/dev/null || true
ip netns del ns_c; ip netns del ns_s
echo "csv: $CSV"
python3 "$PQC_HOME/scripts/summarize.py" "$CSV"
