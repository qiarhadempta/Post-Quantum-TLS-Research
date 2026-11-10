#!/usr/bin/env bash
set -uo pipefail
: "${PQC_HOME:?source env.sh dulu}"
: "${OQS_MODULES:?source env.sh dulu}"
RTT=${1:-100}
PROV="-provider-path $OQS_MODULES -provider oqsprovider -provider default"
DIR="$PQC_HOME/certs"
OUT="$PQC_HOME/results/pcap"
mkdir -p "$OUT"
bash "$PQC_HOME/scripts/ns_setup.sh" "$RTT" 0

cap() {
  local name=$1 group=$2 sig=$3 port=$4
  local pcap="$OUT/${name}_rtt${RTT}.pcap"
  ip netns exec ns_s sysctl -qw net.ipv4.tcp_no_metrics_save=1 2>/dev/null || true
  ip netns exec ns_s ip tcp_metrics flush 2>/dev/null || true
  ip netns exec ns_s openssl s_server -accept "$port" -tls1_3 -cert "$DIR/$name/server.crt" -key "$DIR/$name/server.key" -groups "$group" -sigalgs "$sig" -quiet $PROV >/dev/null 2>&1 &
  local spid=$!
  ip netns exec ns_s tcpdump -i veth_s -nn -s 0 -U -w "$pcap" "tcp port $port" >/dev/null 2>&1 &
  local tpid=$!
  sleep 2
  ip netns exec ns_c openssl s_client -connect "10.0.0.2:$port" -tls1_3 -groups "$group" -sigalgs "$sig" -CAfile "$DIR/$name/root.crt" -verify_return_error -brief $PROV </dev/null >/dev/null 2>&1
  local rc=$?
  sleep 1
  kill -INT "$tpid" 2>/dev/null
  kill "$spid" 2>/dev/null
  wait "$tpid" "$spid" 2>/dev/null
  echo "Scenario $name: s_client exit=$rc, pcap=$pcap, packets=$(tcpdump -nn -r "$pcap" 2>/dev/null | wc -l)"
}

cap A mlkem512 mldsa44 4433
cap B mlkem512 slhdsasha2128f 4434
cap C X25519 rsa_pss_rsae_sha256 4435
chown -R "${SUDO_UID:-0}:${SUDO_GID:-0}" "$PQC_HOME/results" 2>/dev/null || true
ip netns del ns_c; ip netns del ns_s
