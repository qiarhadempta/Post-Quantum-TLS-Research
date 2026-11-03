#!/usr/bin/env bash
set -euo pipefail
: "${OQS_MODULES:?run first: source ~/pqc/env.sh}"
case "$(openssl version)" in
  *3.4.8*) ;;
  *) echo "wrong openssl: $(command -v openssl)"; exit 1 ;;
esac
PROV="-provider-path $OQS_MODULES -provider oqsprovider -provider default"
OUT="$HOME/pqc/certs"
mkdir -p "$OUT" && cd "$OUT"

printf '%s\n' '[req]' 'distinguished_name=dn' '[dn]' > minimal.cnf
printf '%s\n' 'basicConstraints=critical,CA:FALSE' 'keyUsage=critical,digitalSignature' 'extendedKeyUsage=serverAuth' 'subjectAltName=DNS:localhost,IP:127.0.0.1' > ext_server.cnf

gen() {
  local dir=$1 alg=$2
  mkdir -p "$dir"
  (
    cd "$dir"
    openssl req -x509 -new -newkey "$alg" -noenc -keyout root.key -out root.crt -days 365 \
      -subj "/O=PQC TLS Research/CN=PQC Research Root CA" -config ../minimal.cnf \
      -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" $PROV
    openssl req -new -newkey "$alg" -noenc -keyout server.key -out server.csr \
      -subj "/O=PQC TLS Research/CN=localhost" -config ../minimal.cnf $PROV
    openssl x509 -req -in server.csr -CA root.crt -CAkey root.key -CAcreateserial \
      -out server.crt -days 365 -extfile ../ext_server.cnf $PROV
    rm -f server.csr
    for f in root server; do
      printf '%s/%s.crt  DER=%s bytes\n' "$dir" "$f" "$(openssl x509 -in $f.crt -outform DER $PROV | wc -c)"
    done
  )
}
gen A mldsa44
gen B slhdsasha2128f
gen C rsa:2048
