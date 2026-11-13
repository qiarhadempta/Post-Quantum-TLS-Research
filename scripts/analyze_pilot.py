#!/usr/bin/env python3
"""
Analyze tlsbench CSV files (warm-up rows are skipped).

usage: python3 analyze_pilot.py [--hist] file1.csv [file2.csv ...]
"""
import csv, math, sys
from collections import defaultdict

THRESH = (500, 1000, 2000)
SYN_MS = 900.0

def wilson(k, n, z=1.96):
    if n == 0:
        return (float("nan"), float("nan"))
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0.0, c - h), min(1.0, c + h))

def fmt(k, n):
    lo, hi = wilson(k, n)
    return "{:5.1f}% [{:4.1f}-{:4.1f}]".format(100.0 * k / n, 100 * lo, 100 * hi) if n else "n/a"

def median(xs):
    xs = sorted(xs)
    return xs[len(xs) // 2] if xs else float("nan")

args = [a for a in sys.argv[1:] if not a.startswith("--")]
hist = "--hist" in sys.argv[1:]
if not args:
    print(__doc__)
    sys.exit(1)

groups = defaultdict(list)
for path in args:
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            if row["warmup"] == "1":
                continue
            groups[(row["label"], float(row["rtt_ms"]), float(row["loss_pct"]))].append(row)

print("share NOT completed within T (total_ms), with 95% Wilson CI; SYN = tcp_ms > {:.0f} ms".format(SYN_MS))
print("{:<5}{:>5}{:>6}{:>5}{:>5}  {:<20}{:<20}{:<20}{:<20}{:>9}".format(
    "scn", "rtt", "loss", "n", "bad", "SYN retransmit", ">500 ms", ">1000 ms", ">2000 ms", "tls_med*"))
for key in sorted(groups, key=lambda k: (k[1], k[2], k[0])):
    rows = groups[key]
    n = len(rows)
    bad = sum(1 for r in rows if r["status"] != "ok")
    syn = sum(1 for r in rows if float(r["tcp_ms"]) > SYN_MS)
    cols = []
    for t in THRESH:
        k = sum(1 for r in rows if r["status"] != "ok" or float(r["total_ms"]) > t)
        cols.append(fmt(k, n))
    clean = [float(r["tls_ms"]) for r in rows if r["status"] == "ok" and float(r["tcp_ms"]) <= SYN_MS]
    print("{:<5}{:>5g}{:>6g}{:>5d}{:>5d}  {:<20}{:<20}{:<20}{:<20}{:>9.1f}".format(
        key[0], key[1], key[2], n, bad, fmt(syn, n), cols[0], cols[1], cols[2], median(clean)))
print("* median of tls_ms over ok handshakes without a SYN retransmission")

if hist:
    print()
    for key in sorted(groups, key=lambda k: (k[1], k[2], k[0])):
        vals = [float(r["tls_ms"]) for r in groups[key] if r["status"] == "ok"]
        if not vals:
            continue
        bins = defaultdict(int)
        for v in vals:
            bins[min(int(v // 100) * 100, 1500)] += 1
        line = " ".join("{}:{}".format(b, bins[b]) for b in sorted(bins))
        print("{} rtt={:g} loss={:g}  tls_ms bins (start_ms:count, 1500 = >=1500)  {}".format(key[0], key[1], key[2], line))
