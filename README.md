# Handshake Failure Threshold in Post-Quantum TLS 1.3: An Empirical Study of ML-DSA and SLH-DSA Under Controlled Packet Loss

This GitHub repository documents a personal research project comparing the performance of post-quantum digital signature algorithms, specifically ML-DSA (lattice based) and SLH-DSA (hash based) with classical RSA as a baseline in TLS 1.3 under controlled, degraded network conditions.

## Research Overview

Classical cryptographic systems such as RSA are vulnerable to quantum attacks via Shor's algorithm. While NIST has standardized post-quantum alternatives including ML-DSA (FIPS 204) and SLH-DSA (FIPS 205), integrating these primitives into transport layer security introduces significant performance trade-offs due to larger public keys and signature sizes.

This study directly addresses a critical gap in recent literature:
* **Delgado (2026)** evaluated ML-DSA vs SLH-DSA in real Open Quantum Safe (OQS) environments but confined the tests to local environments without network degradation or packet loss.
* **Kampanakis et al. (NDSS 2024)** studied ML-DSA under lossy networks via `tc-netem` but omitted SLH-DSA entirely and only measured successful connections (Time-to-Last-Byte), ignoring connection failure rates.

By establishing an intersection between these methodologies, this research evaluates real ML-DSA and SLH-DSA certificates inside isolated Linux network namespaces, using controlled packet loss to detect **handshake failure thresholds** and model degradation patterns statistically.

## Research Questions

* **RQ1 (Failure Thresholds)** : At what specific packet loss percentages do ML-DSA and SLH-DSA begin to exhibit significant handshake failure rates, and do their failure thresholds differ statistically?
* **RQ2 (Statistical Prediction)** : Can the handshake failure rate be reliably predicted via a statistical combination of certificate chain size, network latency, and packet loss?
* **RQ3 (Linearity Analysis)** : Is the relationship between packet loss and handshake duration linear or non-linear for each algorithm, and where is the inflection point for hash-based signatures?

## Experimental Design

### Scenarios
To isolate the operational impact of the digital signature algorithms, the Key Encapsulation Mechanism (KEM) is locked to `ML-KEM-512` across both post-quantum scenarios. 

| Scenario | KEM | Signature | Approx. Cert Size | Role / Type |
|---|---|---|---|---|
| **A** | ML-KEM-512 | ML-DSA-44 | ~5 KB | PQC Lattice-based (Efficient computation, medium cert) |
| **B** | ML-KEM-512 | SLH-DSA-128f | ~23 KB | PQC Hash-based (Heavy cert, core research focus) |
| **C** | RSA-2048 | RSA-2048 | ~1 KB | Classical Baseline (Industrial reference point) |

*Note: RSA-2048 provides ~112 bits of classical security (slightly below NIST Level 1) but serves as a vital practical baseline representing current industry standards.*

### Network Conditions (via tc-netem)

| Parameter | Tested Values | Total Levels |
|---|---|---|
| **Latency (RTT)** | 0ms, 50ms, 100ms | 3 |
| **Packet Loss** | 0%, 1%, 3%, 5% | 4 |
| **Algorithm Scenario**| Scenario A, Scenario B, Scenario C | 3 |

* **Total Experiment Combinations:** 3 × 4 × 3 = **36 distinct conditions**
* **Sample Size:** 1,000 automated TLS handshakes per condition
* **Total Dataset size:** **36,000 unique handshakes**

### Metrics & Definitions
1. **Handshake Duration (ms):** Monitored from `ClientHello` timestamp to the completion of the `Finished` state.
2. **Handshake Failure Rate (%):** Defined as the percentage of connections per condition that fail to reach the `Finished` state within a **10-second timeout** or terminate prematurely (e.g., connection reset, connection timeout). 
3. **Certificate Chain Size (bytes):** Total size of transmitted public certificates (acting as the primary regression predictor).
4. **CPU Cycles:** Measured on the server-side via `perf` / `rdtsc` to account for computational overhead.

## Software Stack

* **OS:** Ubuntu 22.04 LTS (VirtualBox Environment)
* **Hardware:** Intel Core i7 (11th Gen), 16GB RAM
* **OpenSSL:** v3.0.13
* **OQS Provider:** v0.12.0-dev (built from source using `liboqs`)
  * *OQS naming note: SLH-DSA-128f is instantiated using the `slhdsasha2128f` identifier.*
* **Network Emulation:** Kernel-level `tc-netem` mapping inside isolated **Linux Network Namespaces (`ip netns`)**.
* **Data Analysis:** Python 3 (`pandas`, `statsmodels`, `scipy`, `matplotlib`).

## Current Progress

### Completed
- [x] Build OpenSSL 3 + OQS Provider from source.
- [x] Verify PQC algorithm mapping (`mlkem512`, `mldsa44`, `slhdsasha2128f`).
- [x] Generate custom Root CAs and Server Certificates for Scenarios A, B, and C.

### Baseline Data: Certificate Chain Sizes
| Algorithm Scenario | Root CA Size | Server Cert Size | Total Chain Size (Approx) |
|---|---|---|---|
| **Scenario C (RSA-2048)** | 997 bytes | 993 bytes | ~2 KB |
| **Scenario A (ML-DSA-44)** | 5,348 bytes | 5,336 bytes | ~10.6 KB |
| **Scenario B (SLH-DSA-128f)**| 23,479 bytes | 23,463 bytes | ~47 KB |

*Observation: The SLH-DSA certificate chain is roughly 23x larger than the classical RSA chain, translating to a substantial fragment train over MTU (1500 bytes) standard networks.*

### In Progress
- [ ] Scripting the automated Linux network namespace pairing (`veth` interfaces).
- [ ] Conducting validation ping tests to confirm `tc-netem` latency and loss injections.
- [ ] Writing the automated TLS benchmarking wrapper (`bash` loop wrapping `openssl s_client` outputting to CSV).
- [ ] Executing the 36,000 handshake matrix run.
- [ ] Fitting Logistic Regression (per-handshake success binary) and Polynomial Regressions (for duration non-linearity).

## Repository Structure

```text
pqc-tls-research/
├── certs/               # Generated CA and server certificates (.crt only, keys excluded)
│   ├── rsa_ca.crt
│   ├── mldsa44_server.crt
│   └── slhdsasha2128f_server.crt
├── docs/                # Setup logs, build configurations, and CLI notes
│   └── command.md
├── scripts/             # Automation scripts (Namespace setup, tc injection, and execution)
└── README.md
