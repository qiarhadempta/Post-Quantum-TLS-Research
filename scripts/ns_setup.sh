#!/usr/bin/env bash
set -euo pipefail
RTT_MS=${1:-0}
LOSS=${2:-0}
HALF=$(awk "BEGIN{print $RTT_MS/2}")
command -v ethtool >/dev/null || { echo "ethtool belum terpasang"; exit 1; }

ip netns del ns_c 2>/dev/null || true
ip netns del ns_s 2>/dev/null || true
ip netns add ns_c
ip netns add ns_s
ip link add veth_c type veth peer name veth_s
ip link set veth_c netns ns_c
ip link set veth_s netns ns_s
ip netns exec ns_c ip addr add 10.0.0.1/24 dev veth_c
ip netns exec ns_s ip addr add 10.0.0.2/24 dev veth_s
ip netns exec ns_c ip link set lo up
ip netns exec ns_s ip link set lo up
ip netns exec ns_c ip link set veth_c up
ip netns exec ns_s ip link set veth_s up
ip netns exec ns_c ethtool -K veth_c tso off gso off gro off >/dev/null
ip netns exec ns_s ethtool -K veth_s tso off gso off gro off >/dev/null
ip netns exec ns_c tc qdisc add dev veth_c root netem delay "${HALF}ms" loss "${LOSS}%"
ip netns exec ns_s tc qdisc add dev veth_s root netem delay "${HALF}ms" loss "${LOSS}%"
echo "ready: RTT=${RTT_MS}ms, per-direction loss=${LOSS}%"
