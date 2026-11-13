# Handshake Latency of Post-Quantum Signatures in TLS 1.3 Under Packet Loss

An empirical and analytical study of ML-DSA and SLH-DSA, with RSA as a classical baseline.

**Status:** testbed and measurement tools are ready and a pilot has been run. The full measurement campaign has not been run yet. All numbers below marked *pilot* or *single capture* are preliminary.

## Research Overview

Classical public-key schemes such as RSA and elliptic-curve cryptography are vulnerable to Shor's algorithm on a sufficiently large quantum computer. NIST has standardized post-quantum alternatives, including ML-DSA (FIPS 204, lattice-based) and SLH-DSA (FIPS 205, hash-based). Their keys and signatures are much larger than those of RSA, and in TLS 1.3 the server's authentication data (certificate and signature) travels in the first handshake flight. A larger flight needs more TCP segments, and every segment is exposed to loss.

TCP recovers lost segments, so a handshake normally still succeeds. The cost is **time**: a recovery takes at least one round trip, and sometimes a retransmission timeout. This project measures that time cost for three signature schemes under controlled delay and packet loss, and explains the measurements with a simple model built from segment counts, round trips and retransmission timers.

Closest prior work we are aware of:
* **Delgado (2026)** compared ML-DSA and SLH-DSA with Open Quantum Safe tooling in a local environment, without network impairments.
* **Kampanakis et al. (2024)** studied post-quantum TLS 1.3 under lossy networks with `tc-netem`, with ML-DSA but without SLH-DSA, and reported time-to-last-byte of successful connections.

<!-- TODO: verify both descriptions, and the venue and year of the second paper, against the full texts before publishing this claim -->

## Research Questions (working version)

| # | Question | Relation to the initial plan |
|---|---|---|
| RQ1 | At which per-direction loss levels does the share of handshakes completed within a time limit *T* start to differ between scenarios, and by how much? | Replaces "failure thresholds": in pilot runs TCP recovered every handshake at loss up to 5 %, so failure rate alone does not separate the scenarios |
| RQ2 | How well do server-flight segment count, RTT and loss predict handshake time and the share completed within *T*? | Statistical prediction |
| RQ3 | Is the relation between loss and handshake time linear, and where does it bend? | Linearity analysis |
| RQ4 | *(optional)* How much of the extra latency of SLH-DSA comes from the TCP initial window versus computation? | New |

## Experimental Design

The complete design, analysis plan and noise-control protocol are in [`docs/experimental-design.md`](docs/experimental-design.md). Summary:

### Scenarios

| Scenario | Key exchange | Signature | Server certificate (DER) | Server flight (single capture, RTT 100 ms) |
|---|---|---|---|---|
| **A** | ML-KEM-512 | ML-DSA-44 | 4,110 B | 7,566 B, 6 segments, 1 round |
| **B** | ML-KEM-512 | SLH-DSA-SHA2-128f | 17,494 B | 35,662 B, 25 segments, 2 rounds |
| **C** | X25519 | RSA-2048 (RSA-PSS) | 910 B | 1,466 B, 2 segments, 1 round |

The key exchange is ML-KEM-512 in both post-quantum scenarios, so differences between A and B come from the signature only. Scenario C uses X25519 (TLS 1.3 has no RSA key exchange), so differences between C and the others also include the key exchange. The three certificates share the same subject and extensions. Sizes are DER sizes, not file sizes.

### Network conditions

Emulated with Linux network namespaces, a virtual Ethernet pair and `tc-netem`.

| Parameter | Levels |
|---|---|
| RTT | 0, 50, 100 ms (RTT 0 is a computation baseline) |
| Packet loss, per direction | 0, 1, 2, 3, 5, 10 % |

3 × 6 = **18 conditions**.

### Sampling

Each condition is measured in 10 blocks. A block has 100 handshakes per scenario, interleaved in random order, after 10 discarded warm-up handshakes per scenario. The order of blocks is randomized. This gives 1,000 handshakes per scenario per condition and **54,000 measured handshakes** in total. Every handshake is a full handshake (new TCP connection, no session resumption). Hard timeout: 10 s.

### Metrics

| Metric | Definition |
|---|---|
| `tcp_ms` | TCP connection setup time |
| `tls_ms` | TLS handshake time on the client, excluding the TCP handshake |
| `total_ms` | `tcp_ms` + `tls_ms` |
| Share not completed within *T* | share of handshakes with `total_ms` > *T*, for *T* = 0.5, 1, 2, 5 s (failed and timed-out handshakes count as not completed) |
| SYN retransmission share | share with `tcp_ms` > 900 ms |
| Bytes, segments, rounds, retransmissions | from packet captures and TCP counters at representative conditions |
| Computation time | sign and verify times measured separately, without a network |

CPU-cycle counters are not used, because hardware counters are unreliable inside a virtual machine.

### Analysis

Confidence intervals use a bootstrap over blocks (the block, not the handshake, is the unit of analysis). Planned comparisons are B versus A, B versus C and A versus C. The analysis plan will be frozen before the campaign.

## Preliminary Observations (pilot)

From about 5,400 pilot handshakes (RTT 100 ms with loss 0, 1, 3 and 5 %; RTT 0 and 50 ms with no loss), 300 handshakes per scenario per condition. These are not campaign results.

* No handshake failed with a 5 s timeout.
* Handshakes slower than 1 s occurred at the same rate as SYN retransmissions, in every scenario.
* SLH-DSA had the largest share of handshakes slower than 500 ms at 3 % and 5 % loss; most of the difference is in the 0.5 to 1 s band.
* The server's initial congestion window was observed to be 10 segments; the SLH-DSA flight needed a second round trip.
* Timing of SLH-DSA drifted between runs, which is consistent with CPU contention in the virtual machine but has not been measured directly. See the noise-control protocol in the design document.

## Software Stack

| Component | Version |
|---|---|
| Host | Windows 11 Pro, Intel Core i7 (11th gen), 16 GB RAM |
| Hypervisor | VirtualBox 7.1.x |
| Guest OS | Ubuntu 24.04.3 LTS, kernel 7.0.0-31-generic, 4 vCPUs, 8 GB RAM |
| OpenSSL | 3.4.8 (built locally) |
| liboqs | 0.16.0 |
| oqs-provider | 0.12.0 |
| Network emulation | `tc-netem` in Linux network namespaces |
| Measurement client | purpose-built C program (`tlsbench`) |
| Analysis | Python 3 |

OpenSSL 3.4.8 was chosen because the system OpenSSL (3.0.13) lacks the provider interface for post-quantum signatures in TLS 1.3, and because, according to the oqs-provider 0.12.0 documentation, SLH-DSA cannot be used in TLS through the provider on OpenSSL 3.5 or later. All algorithms therefore come from one implementation (liboqs). Build steps, versions, commit hashes and verification output are in [`docs/setup-log.md`](docs/setup-log.md).

*Naming note:* SLH-DSA-SHA2-128f is `slhdsasha2128f` in oqs-provider and `SLH_DSA_PURE_SHA2_128F` in liboqs.

## Progress

### Completed
- [x] Build OpenSSL 3.4.8, liboqs 0.16.0 and oqs-provider 0.12.0; verify linking and algorithms
- [x] Regenerate root and server certificates for scenarios A, B and C; measure DER sizes
- [x] TLS 1.3 handshakes succeed in all three scenarios; ML-KEM-512 confirmed in the key exchange
- [x] Network namespaces and `tc-netem`; delay and loss validated with `ping`
- [x] Packet captures of one handshake per scenario at RTT 0, 50 and 100 ms
- [x] Timed measurement client and pilot runs

### In progress
- [ ] Compute-only measurements of signing and verification, and noise estimation
- [ ] Multi-scenario client, concurrent server and campaign script
- [ ] Rehearsal run and freezing of the analysis plan

### Planned
- [ ] Measurement campaign (about 54,000 handshakes)
- [ ] Analytical model, statistical analysis and figures
- [ ] Manuscript

## Repository Structure

```text
Post-Quantum-TLS-Research/
├── certs/      # Public certificates only (.crt); private keys are never committed
├── docs/       # setup-log.md (environment), experimental-design.md (design and analysis plan)
├── scripts/    # certificate generation, network namespace setup, packet capture,
│               # measurement client, benchmark wrappers and analysis scripts
└── README.md
```
