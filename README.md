# Experimental Design

**Status:** working draft v1, to be frozen before the measurement campaign.
Items marked **(proposed)** are not final until confirmed.
Last updated: 2026-11-13

This document describes what will be measured, how, and how the results will be analysed. It supersedes the experimental-design section of the initial README, which assumed failure rate as the main metric. Pilot runs showed that TCP recovers almost all lost segments, so the main question is now the time cost of that recovery (see [Changes from the initial design](#changes-from-the-initial-design)).

## 1. Objective

Measure how the signature algorithm used for server authentication changes the TLS 1.3 handshake under controlled delay and packet loss, and explain the differences with a simple model built from segment counts, round trips and TCP retransmission timers.

Primary outcome: the share of handshakes that are **not** completed within a time limit $T$, for $T \in \{0.5, 1, 2, 5\}$ s.

## 2. Scenarios

| Scenario | Key exchange | Signature | Server certificate (DER) | Server flight (measured, RTT 100 ms, no loss) |
|---|---|---|---|---|
| A | ML-KEM-512 | ML-DSA-44 | 4,110 B | 7,566 B, 6 segments, 1 round |
| B | ML-KEM-512 | SLH-DSA-SHA2-128f | 17,494 B | 35,662 B, 25 segments, 2 rounds |
| C | X25519 | RSA-2048 (RSA-PSS) | 910 B | 1,466 B, 2 segments, 1 round |

- Certificates of the three scenarios share the same subject and extensions, so size differences come from the algorithms only.
- Scenario C uses a different key exchange (X25519), so A/B versus C also differs in key exchange. This is reported as a limitation. **(proposed)** An extra scenario with X25519 and ML-DSA-44 can separate the two effects.
- The server flight sizes come from a single packet capture per scenario and will be re-measured in the campaign.
- The initial congestion window was observed to be 10 segments (B sent 10 segments, then 15 more about one RTT later).

## 3. Network conditions

Emulated with Linux network namespaces, a virtual Ethernet pair and `tc-netem`.

| Factor | Levels |
|---|---|
| RTT | 0, 50, 100 ms (RTT/2 applied on each end of the virtual link) |
| Packet loss, applied **per direction** | 0, 1, 2, 3, 5, 10 % |

This gives 3 × 6 = **18 conditions**. Loss is applied in both directions, so a ping round trip sees roughly $1-(1-p)^2$. RTT 0 is a computation baseline, not a realistic network.

## 4. Sampling and randomization

- **Block** = one network condition, 300 measured handshakes: 100 per scenario, scenarios **interleaved in random order** within the block, preceded by 10 warm-up handshakes per scenario (discarded, recorded and flagged).
- **10 blocks per condition** → 1,000 measured handshakes per scenario per condition; 180 blocks; 54,000 measured handshakes in total.
- The **order of the 180 blocks is randomized** (random seed stored in the run manifest).
- **(proposed)** **Calibration blocks** (RTT 0, loss 0, 30 handshakes per scenario) are inserted at regular intervals to track drift of the testbed over the campaign.
- Every handshake is a full handshake: new TCP connection, new TLS session, no resumption, no session tickets.
- Hard timeout per handshake: **D = 10 s**.

Rough duration estimate from pilot averages: about 4 to 5 hours, to be recomputed once the campaign script exists.

## 5. Measurement

Client: purpose-built C program (`tlsbench`) using the monotonic clock.

| Field | Definition |
|---|---|
| `tcp_ms` | start of `connect()` until the TCP connection is established |
| `tls_ms` | start of the TLS handshake until it completes on the client (client Finished sent); excludes the TCP handshake |
| `total_ms` | `tcp_ms` + `tls_ms`; the time limits $T$ and $D$ apply to this value |
| `status` | `ok`, `timeout_tcp`, `timeout_tls`, `tcp_error`, `tls_error` |
| SYN retransmission | `tcp_ms` > 900 ms (the initial SYN retransmission timer is 1 s) |

One CSV line is written and flushed per handshake. Handshakes that fail or time out count as not completed for every $T$.

Server: **(proposed)** a small server that handles each connection in its own process, replacing `openssl s_server`, which serves one connection at a time and can hold up the next connection under high loss.

Packet captures (`tcpdump`) are taken separately at representative conditions, to measure bytes, segments and rounds. They are not recorded during the timed campaign.

## 6. Analysis plan (to be frozen before the campaign)

- **Unit of analysis is the block.** Handshakes within a block share conditions and time, so they are not independent. Confidence intervals use a bootstrap over blocks (10 per cell).
- **Primary comparisons:** B versus A, B versus C, A versus C, as differences in the share not completed within $T$, per condition.
- **Secondary:** percentiles of `tls_ms` and `total_ms`; share of SYN retransmissions; `tls_ms` among handshakes without a SYN retransmission.
- **Model:** predictors from the server flight (segments, rounds), RTT and loss; compare predicted and measured handshake time, and report the prediction error. The shape of the loss-versus-time relation (linear or not) is examined with polynomial regression, as in the original design.
- **Multiple comparisons:** four thresholds and 18 conditions; use a correction (for example Holm) or label the secondary results exploratory. Decide before the campaign.
- **No outlier removal.** Blocks may be flagged only by a rule defined from a rehearsal run **before** the campaign (based on calibration blocks).

## 7. Working research questions

These keep the questions of the initial README and add the explanation of the mechanism.

| # | Question | Relation to initial README |
|---|---|---|
| RQ1 | At which loss levels does the share of handshakes completed within $T$ start to differ between scenarios, and by how much? | Replaces "failure thresholds" |
| RQ2 | How well do segment count, RTT and loss predict handshake time and the share completed within $T$? | Statistical prediction |
| RQ3 | Is the relation between loss and handshake time linear, and where does it bend? | Linearity analysis |
| RQ4 | **(optional)** How much of B's extra latency comes from the TCP initial window versus computation? Tested by enlarging the server's initial window. | New |

Descriptive baseline from packet captures: bytes, segments and rounds per scenario (section 2).

## 8. Noise control protocol

All measurements run in a virtual machine that shares CPU with the host, so absolute timings are specific to this testbed. Before and during the campaign:

**Host (Windows)**
- Power cable connected; power mode set to the highest performance; sleep, hibernate and lid-close actions disabled.
- Close browsers, chat and meeting apps, and sync clients; pause Windows Update for the duration; no scheduled scans during the run.
- Do not use the machine for anything else while the campaign runs. Provide good ventilation (sustained load for hours may cause thermal throttling).
- Check that VirtualBox runs with hardware virtualization and not in a slower compatibility mode.
- Record the idle CPU usage of the host for a few minutes before starting.

**Virtual machine and guest (Ubuntu)**
- Close Firefox, Wireshark and any other application; disable automatic suspend and screen lock; stop automatic updates and background indexing during the run.
- Run the campaign inside `tmux` so it survives a crash of the graphical session.
- Pin the client and the server to different virtual CPUs.
- Take a VM snapshot before the campaign, not during it; change no setting and install nothing during the run.

**Quantifying the remaining noise**
- Compute-only measurements of signing and verification for each algorithm, thousands of repetitions, without any network, in a quiet and a busy state; reported as distributions.
- A rehearsal (about 30 minutes) with calibration blocks to estimate drift and to set the block-flagging rule.
- A run manifest: Windows and VirtualBox versions, power mode, CPU model, kernel version, software versions and commit hashes, script commit, random seed, SHA-256 of every raw CSV file.

## 9. Pilot findings that shaped the design

Pilot at RTT 100 ms with loss 0, 1, 3, 5 % (300 handshakes per scenario), and RTT 0 and 50 ms with loss 0:

- No handshake failed at a 5 s timeout in the 5,400 pilot handshakes. Failure rate alone cannot separate the scenarios at these loss levels.
- Handshakes slower than 1 s occurred at the same rate as SYN retransmissions in all conditions, and independently of the scenario.
- SLH-DSA (B) had the largest share of handshakes slower than 500 ms at 3 % and 5 % loss; most of the difference lies in the 0.5 to 1 s band.
- Computation of B is partly hidden behind network waiting time at RTT 50 and 100 ms. The median of B drifted between runs (for example 275 ms versus 234 ms at RTT 100 ms, no loss), and B at RTT 0 showed a heavy tail; both are consistent with CPU contention but this has not been measured directly.
- A single failed handshake in a smoke test (loss 1 %, 3 s limit) had a SYN retransmission followed by a further delay.

## 10. Changes from the initial design

| Item | Initial | Now |
|---|---|---|
| Main metric | Handshake failure rate within 10 s | Share not completed within $T$ (0.5, 1, 2, 5 s); hard timeout 10 s |
| Scenario C key exchange | RSA-2048 (not possible in TLS 1.3) | X25519 |
| Loss levels | 0, 1, 3, 5 % | 0, 1, 2, 3, 5, 10 % |
| Conditions | 36 (3 RTT × 4 loss × 3 scenarios) | 18 conditions; scenarios interleaved inside each condition |
| Samples | 1,000 per condition | 1,000 per scenario per condition, 10 blocks of 100 |
| Timing tool | `openssl s_client` in a shell loop | purpose-built C client |
| Certificate size | file size (PEM) | DER size |
| Finer sweep around a failure threshold | planned | replaced by a sweep around the loss level where the share completed within $T$ diverges |

## 11. Limitations

- Virtual machine sharing CPU with the host; virtual Ethernet instead of a physical network.
- TCP only; loss is random and independent unless a burst model is added.
- One key-exchange group per scenario; scenario C differs in key exchange.
- Test client and server instead of production software; single host.
- The certificates do not contain the IP address of the server, so hostname verification is not performed in the timed client.

## 12. Open items

- [ ] Confirm the items marked (proposed).
- [ ] Rehearsal and noise measurements (section 8).
- [ ] Concurrent server, multi-scenario client and campaign script.
- [ ] Freeze the analysis plan (section 6).
- [ ] Update the README so that it links to this document.
