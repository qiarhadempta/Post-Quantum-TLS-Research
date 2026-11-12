#!/usr/bin/env python3
"""Summarize tlsbench CSV files. usage: python3 summarize.py file1.csv [file2.csv ...]"""
import csv, math, sys
from collections import defaultdict

def pct(xs, q):
    if not xs:
        return float("nan")
    xs = sorted(xs)
    k = max(0, math.ceil(q * len(xs)) - 1)
    return xs[k]

groups = defaultdict(list)
for path in sys.argv[1:]:
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            if row["warmup"] == "1":
                continue
            groups[(row["label"], float(row["rtt_ms"]), float(row["loss_pct"]), float(row["deadline_ms"]))].append(row)

hdr = ("label", "rtt", "loss%", "D_ms", "n", "ok", "timeout", "error", "tls_med", "tls_p95", "tls_p99", "tls_mean", "tcp_med")
print("{:<6}{:>6}{:>7}{:>8}{:>6}{:>6}{:>9}{:>7}{:>10}{:>10}{:>10}{:>10}{:>9}".format(*hdr))
for key in sorted(groups):
    rows = groups[key]
    ok = [r for r in rows if r["status"] == "ok"]
    to = [r for r in rows if r["status"].startswith("timeout")]
    er = [r for r in rows if r["status"] not in ("ok",) and not r["status"].startswith("timeout")]
    tls = [float(r["tls_ms"]) for r in ok]
    tcp = [float(r["tcp_ms"]) for r in ok]
    mean = sum(tls) / len(tls) if tls else float("nan")
    print("{:<6}{:>6g}{:>7g}{:>8g}{:>6d}{:>6d}{:>9d}{:>7d}{:>10.1f}{:>10.1f}{:>10.1f}{:>10.1f}{:>9.1f}".format(
        key[0], key[1], key[2], key[3], len(rows), len(ok), len(to), len(er),
        pct(tls, 0.5), pct(tls, 0.95), pct(tls, 0.99), mean, pct(tcp, 0.5)))
