# Post-Quantum TLS 1.3 Performance Analysis

This repository documents an independent research project comparing the 
performance of post-quantum digital signature algorithms — ML-DSA (lattice-based) 
and SLH-DSA (hash-based) — against classical RSA in TLS 1.3, under degraded 
network conditions.

## Research Overview

Classical cryptographic systems such as RSA are vulnerable to quantum attacks 
via Shor's algorithm. NIST has standardized post-quantum alternatives including 
ML-DSA (FIPS 204) and SLH-DSA (FIPS 205). However, integrating these algorithms 
into real protocols like TLS 1.3 introduces performance challenges — particularly 
under realistic, degraded network conditions.

This study fills a specific gap: prior work either tested PQC in ideal network 
environments (Delgado, 2026) or simulated certificate sizes using RSA-based chains 
rather than real PQC implementations (Kampanakis, 2024). This research uses actual 
ML-DSA and SLH-DSA certificates in live TLS 1.3 handshakes under emulated 
network degradation.

## Research Questions

- **RQ1** — How does handshake duration differ between ML-DSA, SLH-DSA, and RSA 
  under ideal network conditions?
- **RQ2** — How does increasing network latency and packet loss affect handshake 
  duration of each algorithm?
- **RQ3** — To what extent does certificate chain size contribute to performance 
  degradation under degraded network conditions?

## Experimental Design

### Scenarios

| Scenario | KEM | Signature | Type |
|---|---|---|---|
| A | ML-KEM-512 | ML-DSA-44 | Pure lattice-based |
| B | ML-KEM-512 | SLH-DSA-128f (SHA-2) | Lattice KEM + Hash signature |
| C | RSA-2048 | RSA-2048 | Classical baseline |

All scenarios use **NIST Security Level 1**.

### Network Conditions (via tc-netem)

| Parameter | Values |
|---|---|
| Latency | 0ms, 50ms, 100ms |
| Packet Loss | 0%, 1%, 3% |

Total: **27 experiment combinations** (3 scenarios × 3 latency × 3 packet loss)

### Metrics

1. **Handshake Duration (ms)** — time from ClientHello to Finished
2. **Certificate Chain Size (bytes)** — total bytes transmitted during handshake
3. **CPU Cycles** — computational cost on server-side

## Software Stack

- Ubuntu 22.04 (VirtualBox)
- OpenSSL 3.0.x
- OQS Provider 0.12.0 (liboqs)
- tc-netem (network emulation)

## Current Progress

### Completed
- [x] OpenSSL + OQS Provider setup and configuration
- [x] PQC algorithm verification (ML-DSA, SLH-DSA, ML-KEM)
- [x] Certificate generation for all 3 scenarios

### First Data Point — Certificate Chain Size

<img width="614" height="185" alt="image" src="https://github.com/user-attachments/assets/44a8a9b6-6545-4cb6-a645-6689c82e2b34" />

| Algorithm | Root CA | Server Cert |
|---|---|---|
| RSA-2048 | 997 bytes | 993 bytes |
| ML-DSA-44 | 5,348 bytes | 5,336 bytes |
| SLH-DSA-128f | 23,479 bytes | 23,463 bytes |

SLH-DSA certificates are ~23x larger than RSA — a preview of the performance 
impact expected under degraded network conditions.

### In Progress
- [ ] Linux namespace setup (isolated client-server environment)
- [ ] tc-netem network emulation
- [ ] TLS handshake measurement scripts
- [ ] Experiment execution (27 combinations)
- [ ] Data analysis and visualization

## Repository Structure
pqc-tls-research/
├── certs/              # Generated certificates (.crt only, keys excluded)
│   ├── rsa_.crt
│   ├── mldsa44_.crt
│   └── slhdsa128f_*.crt
├── docs/               # Setup documentation and commands
│   └── command.md
└── README.md

## References
- Delgado, J.L. (2026). Signature Placement in Post-Quantum TLS Certificate 
  Hierarchies. arXiv:2604.06100
- Kampanakis, P. & Childs-Klein, W. (2024). The impact of data-heavy, 
  post-quantum TLS 1.3 on the Time-To-Last-Byte. MADWeb 2024.
- NIST FIPS 203 (ML-KEM), FIPS 204 (ML-DSA), FIPS 205 (SLH-DSA)
