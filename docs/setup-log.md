# Enviromental Set Up
This document describes the experimental environment used in this project

## 1. Requirements and pre-flight checks
### Tested Configuration
| Item | Value |
|---|---|
| Hypervisor | VirtualBox 7.1.x (Guest Additions 7.1.10) |
| Guest OS | Ubuntu 24.04.3 LTS |
| Guest kernel | 7.0.0-31-generic |
| vCPUs | 4 |
| Guest RAM | 8000 MB configured (7.6 GiB visible) |
| Acceleration | Nested Paging, KVM paravirtualization |
| Virtual disk | 60 GB (VDI) |
| Host | Intel Core i7 (11th Gen), 16 GB RAM, Windows 11 Pro |

### Recommended Resources
- 4 vCPUs and 6-8 GB of RAM for the guest. Builds are run with `make -j4`
- For disk size, at least 40 GB of free space in the guest. The toolchain and builds are estimated at roughly 5-7 GB, and packet captures and result files need additional space. A 25 GB root partition was found to be too small for this workload.
- Internet access from the guest, because the build steps clone repositories from GitHub.

### Checks
The experiment depends on two kernel features, `tc-netem` (to inject delay and packet loss) and network namespaces (to isolate client and server). Verify both before starting with these commands:
```bash
lsb_release -a
uname -r
nproc
free -h
df -h /
sudo modprobe sch_netem && lsmod | grep netem
sudo ip netns add uji && ip netns list && sudo ip netns del uji
```

Expected result: `sch_netem` appears in the module list, and the namespace `uji` is created and listed. In the tested configuration the output was:
```text
sch_netem              28672  0
uji
```
---

## 2. Dependencies and Workspace Layout
```bash
sudo apt update
sudo apt install -y build-essential cmake ninja-build git curl wget python3 python3-pip iproute2 tcpdump libssl-dev pkg-config
mkdir -p ~/pqc/{src,build,certs,results,logs}
cd ~/pqc && git init
```

All work lives under `~/pqc`, so that everything can be removed by deleting a single folder. The system OpenSSL is never modified.

---

## 3. Build OpenSSL
OpenSSL is built before liboqs, so that liboqs and oqs-provider link against this exact OpenSSL and not the system one.

```bash
cd ~/pqc/src
git clone --branch openssl-3.4.8 --depth 1 https://github.com/openssl/openssl.git
cd openssl
./Configure --prefix=$HOME/pqc/openssl --openssldir=$HOME/pqc/openssl/ssl --libdir=lib shared -Wl,-rpath,$HOME/pqc/openssl/lib
make -j4
make install_sw
```

### Verification
```bash
~/pqc/openssl/bin/openssl version
ldd ~/pqc/openssl/bin/openssl | grep -E "libssl|libcrypto"
```

output:
```text
OpenSSL 3.4.8 29 Sep 2026 (Library: OpenSSL 3.4.8 29 Sep 2026)
	libssl.so.3 => /home/chantiqia/pqc/openssl/lib/libssl.so.3 (0x000077a00afc7000)
	libcrypto.so.3 => /home/chantiqia/pqc/openssl/lib/libcrypto.so.3 (0x000077a00aa00000)
```

<img width="987" height="141" alt="image" src="https://github.com/user-attachments/assets/27c3940f-c315-41cf-af23-c4ca69d4c649" />

---

## 4. BUild liboqs 0.16.0
liboqs is an open source library for quantum safe cryptography. Run these commands below to set it up:

```bash
cd ~/pqc/src
git clone --branch 0.16.0 --depth 1 https://github.com/open-quantum-safe/liboqs.git
cd liboqs && mkdir build && cd build
cmake -GNinja .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=$HOME/pqc/liboqs \
  -DOPENSSL_ROOT_DIR=$HOME/pqc/openssl \
  -DBUILD_SHARED_LIBS=ON \
  -DOQS_BUILD_ONLY_LIB=ON \
  -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON
ninja -j4
ninja install
```

### Verification 1: linked against the local OpenSSL

This checks that liboqs was compiled and is loaded against the OpenSSL built in Section 3, not the system one.

```bash
grep -E "OQS_USE_OPENSSL|OPENSSL_CRYPTO_LIBRARY:|OPENSSL_INCLUDE_DIR:" ~/pqc/src/liboqs/build/CMakeCache.txt
ldd ~/pqc/liboqs/lib/liboqs.so | grep -E "libcrypto|libssl"
readelf -d ~/pqc/liboqs/lib/liboqs.so.0.16.0 | grep -E "RUNPATH|RPATH"
```

Output:
```text
OPENSSL_CRYPTO_LIBRARY:FILEPATH=/home/chantiqia/pqc/openssl/lib/libcrypto.so
OPENSSL_INCLUDE_DIR:PATH=/home/chantiqia/pqc/openssl/include
OQS_USE_OPENSSL:BOOL=ON
	libcrypto.so.3 => /home/chantiqia/pqc/openssl/lib/libcrypto.so.3 (0x00007ffbd1000000)
 0x000000000000001d (RUNPATH)            Library runpath: [/home/chantiqia/pqc/openssl/lib]
```

<img width="1661" height="183" alt="image" src="https://github.com/user-attachments/assets/286efdaf-0a68-426a-8f54-33f5564e9258" />

### Verification 2: exact versions

The commit hashes pin the exact source that was built.

```bash
git -C ~/pqc/src/liboqs describe --tags
git -C ~/pqc/src/liboqs rev-parse HEAD
git -C ~/pqc/src/openssl rev-parse HEAD
PKG_CONFIG_PATH=$HOME/pqc/liboqs/lib/pkgconfig pkg-config --modversion liboqs
```

Output:

```text
0.16.0
5a1a854b0dc9f2141bdc771c555ee60c37950183
e72c946f6f6d94c8ba5119acb25340b7b6b2073f
0.16.0
```

<img width="978" height="183" alt="image" src="https://github.com/user-attachments/assets/fe21dcfc-0881-4b78-99f3-df467c2218f7" />


| Component | Version | Commit |
|---|---|---|
| liboqs | 0.16.0 | `5a1a854b0dc9f2141bdc771c555ee60c37950183` |
| OpenSSL | 3.4.8 | `e72c946f6f6d94c8ba5119acb25340b7b6b2073f` |

### Verification 3: the algorithms work

The first two checks only show that the right libraries are linked. This one runs the algorithms. [`scripts/verify_liboqs.c`](../scripts/verify_liboqs.c) performs a key generation plus an encapsulate/decapsulate (or sign/verify) round trip for the three algorithms used in this study and prints their sizes.

```bash
cd ~/Post-Quantum-TLS-Research/scripts
gcc verify_liboqs.c -I$HOME/pqc/liboqs/include -L$HOME/pqc/liboqs/lib -loqs -Wl,-rpath,$HOME/pqc/liboqs/lib -o verify_liboqs
./verify_liboqs
```

Output:

```text
liboqs version: 0.16.0
[KEM] ML-KEM-512     pk=800 ct=768 ss=32 roundtrip=OK
[SIG] ML-DSA-44                  pk=1312 sig=2420 sign=0.28 ms verify=OK
[SIG] SLH_DSA_PURE_SHA2_128F     pk=32 sig=17088 sign=23.55 ms verify=OK
```

<img width="1269" height="180" alt="image" src="https://github.com/user-attachments/assets/11f39354-b0b2-4e2b-bc0d-e5bd7ef12510" />


All round trips succeed, and the sizes match the FIPS 203/204/205 parameter sets for ML-KEM-512, ML-DSA-44 and SLH-DSA-SHA2-128f. The signing times are a single, un-warmed measurement inside a VM and are not benchmark data.


### Algorithm names across layers

| Algorithm | liboqs name | oqs-provider name |
|---|---|---|
| ML-KEM-512 | `ML-KEM-512` | `mlkem512` |
| ML-DSA-44 | `ML-DSA-44` | `mldsa44` |
| SLH-DSA-SHA2-128f | `SLH_DSA_PURE_SHA2_128F` | `slhdsasha2128f` |

---

## 5. Build oqs-provider 0.12.0
<to do, update soon>

---

## 6. TLS 1.3 handshake test
<to do, update soon>
