# Environmental Set Up
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
- 4 vCPUs and 6-8 GB of RAM for the guest. Builds are run with `make -j4
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

### 4. BUild liboqs 0.16.0
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
---

### 5. Build oqs-provider 0.12.0
<to do, update soon>

---

### 6. TLS 1.3 handshake test
<to do, update soon>
