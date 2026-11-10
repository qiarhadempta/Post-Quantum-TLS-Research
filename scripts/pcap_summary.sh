#!/usr/bin/env bash
# usage: bash pcap_summary.sh [RTT_ms]
RTT=${1:-100}
OUT="$HOME/pqc/results/pcap"
for s in A B C; do
  f="$OUT/${s}_rtt${RTT}.pcap"
  echo "== Scenario $s (RTT=${RTT}ms) =="
  echo "server->client (waktu_relatif_detik:byte_payload):"
  tcpdump -nn -tt -r "$f" 'tcp and src host 10.0.0.2' 2>/dev/null | awk '{ len=0; for(i=1;i<=NF;i++) if($i=="length") len=$(i+1); if(len>0){ if(!t0) t0=$1; n++; b+=len; printf "%.3f:%d ", $1-t0, len } } END { printf "\n  data_packets=%d  payload_bytes=%d\n", n, b }'
  echo "client->server:"
  tcpdump -nn -tt -r "$f" 'tcp and src host 10.0.0.1' 2>/dev/null | awk '{ len=0; for(i=1;i<=NF;i++) if($i=="length") len=$(i+1); if(len>0){ n++; b+=len } } END { printf "  data_packets=%d  payload_bytes=%d\n", n, b }'
  echo
done
