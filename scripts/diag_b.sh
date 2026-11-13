#!/usr/bin/env bash
set -uo pipefail
: "${PQC_HOME:?}"
: "${OQS_MODULES:?}"
RTT=${1:-0}
N=${2:-100}
PROV="-provider-path $OQS_MODULES -provider oqsprovider -provider default"
DIR="$PQC_HOME/certs"
BENCH="$PQC_HOME/scripts/tlsbench"
OUT="$PQC_HOME/results/diag"
mkdir -p "$OUT"
CSV="$OUT/B_rtt${RTT}_diag.csv"
rm -f "$CSV"
[ -x "$BENCH" ] || { echo "tlsbench belum dikompilasi: $BENCH"; exit 1; }

bash "$PQC_HOME/scripts/ns_setup.sh" "$RTT" 0
ip netns exec ns_s openssl s_server -accept 4434 -tls1_3 \
  -cert "$DIR/B/server.crt" -key "$DIR/B/server.key" \
  -groups mlkem512 -sigalgs slhdsasha2128f -num_tickets 0 -no_cache -quiet $PROV >/dev/null 2>&1 &
spid=$!
sleep 2
ip netns exec ns_c "$BENCH" -a 10.0.0.2 -p 4434 -g mlkem512 -s slhdsasha2128f \
  -c "$DIR/B/root.crt" -n "$N" -w 10 -d 5000 -l B -r "$RTT" -L 0 -o "$CSV" -m "$OQS_MODULES"

PAT="TcpRetransSegs|TcpExtTCPTimeouts|TcpExtTCPFastRetrans|TcpExtTCPLossProbes|TcpExtTCPSpuriousRTOs|TcpExtDelayedACKs"
for ns in ns_c ns_s; do
  echo "== TCP counters in $ns (since the namespace was created; handshakes run: $((N + 10))) =="
  ip netns exec "$ns" nstat -az 2>/dev/null | grep -E "$PAT"
done
echo "== qdisc statistics =="
echo "-- ns_s veth_s"
ip netns exec ns_s tc -s qdisc show dev veth_s | grep -E "Sent|dropped"
echo "-- ns_c veth_c"
ip netns exec ns_c tc -s qdisc show dev veth_c | grep -E "Sent|dropped"
echo "== interface drops =="
ip netns exec ns_s ip -s link show veth_s | sed -n '3,6p'
ip netns exec ns_c ip -s link show veth_c | sed -n '3,6p'

kill "$spid" 2>/dev/null
wait "$spid" 2>/dev/null
chown -R "${SUDO_UID:-0}:${SUDO_GID:-0}" "$PQC_HOME/results" 2>/dev/null || true
ip netns del ns_c; ip netns del ns_s
python3 "$PQC_HOME/scripts/summarize.py" "$CSV"
python3 "$PQC_HOME/scripts/analyze_pilot.py" --hist "$CSV"
