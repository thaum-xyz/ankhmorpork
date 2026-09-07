#!/bin/bash

# Writes a kubeconfig that authenticates to the cluster through pocket-id, for
# someone who has just been added to a `k8s-*` group. See
# docs/how-to/log-in-with-kubectl.md.
#
# Everything except the CA comes out of metal/group_vars/k3s.yml -- issuer,
# client ID and the kube-vip address -- so this cannot disagree with what the
# API server is actually configured to accept, and no copy of those values has
# to be maintained in the documentation.
#
# The CA is fetched at run time rather than published, because it is a trust
# anchor: keeping it secret is pointless (the API server hands it to every
# unauthenticated TLS client) but keeping it *correct* is what stops kubectl
# trusting an impostor and handing over a bearer token. Two ways to get it:
#
#   - default: from the TLS handshake, trust-on-first-use. Fine on the house
#     network, and the SHA-256 fingerprint is printed so it can be confirmed
#     out of band with someone who already has access.
#   - `-n <node>`: over SSH from a control-plane node, which is authoritative
#     and needs no such confirmation. Requires node access, so this is the
#     admin path.
#
# Usage: ./hack/mkkubeconfig.sh [-o out] [-s server] [-n node] [-f] [--no-verify]

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VARS="${REPO_ROOT}/metal/group_vars/k3s.yml"
# Homebrew's python3 has no pyyaml on this machine; the system one does.
PYTHON=/usr/bin/python3

OUT="${HOME}/.kube/clusters/ankhmorpork-oidc"
SERVER=""
NODE=""
FORCE=0
VERIFY=1

while [ $# -gt 0 ]; do
  case "$1" in
    -o) OUT="$2"; shift 2 ;;
    -s) SERVER="$2"; shift 2 ;;
    -n) NODE="$2"; shift 2 ;;
    -f) FORCE=1; shift ;;
    --no-verify) VERIFY=0; shift ;;
    -h|--help) sed -n '3,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

die() { echo "error: $*" >&2; exit 1; }

command -v openssl >/dev/null || die "openssl is required"
[ -r "$VARS" ] || die "cannot read $VARS -- run this from a checkout of the repository"

read -r ISSUER CLIENT_ID VIP <<<"$(
  "$PYTHON" - "$VARS" <<'PY'
import sys, yaml
v = yaml.safe_load(open(sys.argv[1]))
missing = [k for k in ("k3s_oidc_issuer_url", "k3s_oidc_client_id", "kube_vip_ip") if not v.get(k)]
if missing:
    sys.exit("group_vars is missing or has empty: " + ", ".join(missing))
print(v["k3s_oidc_issuer_url"], v["k3s_oidc_client_id"], v["kube_vip_ip"])
PY
)" || die "could not read the OIDC settings from $VARS"

[ -n "$ISSUER" ] && [ -n "$CLIENT_ID" ] && [ -n "$VIP" ] || die "empty OIDC settings in $VARS"
[ -n "$SERVER" ] || SERVER="https://${VIP}:6443"

if [ -e "$OUT" ] && [ "$FORCE" -eq 0 ]; then
  die "$OUT exists; pass -f to overwrite"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ -n "$NODE" ]; then
  echo "Reading the CA from ${NODE} (authoritative)..."
  ssh -o ConnectTimeout=10 "$NODE" 'sudo cat /var/lib/rancher/k3s/server/tls/server-ca.crt' \
    > "${TMP}/ca.pem" 2>/dev/null
  [ -s "${TMP}/ca.pem" ] || die "could not read the CA from ${NODE}"
else
  hostport="${SERVER#https://}"
  echo "Fetching the CA from ${hostport} over TLS (trust-on-first-use)..."
  openssl s_client -showcerts -connect "$hostport" </dev/null 2>/dev/null \
    | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' > "${TMP}/chain.pem"
  [ -s "${TMP}/chain.pem" ] || die "no certificates offered by ${hostport} -- wrong address, or not reachable from here"

  # The API server sends leaf then CA. Split them so the chain can be checked
  # rather than assumed: a single-cert chain means the CA was not offered, and
  # guessing would hand back the leaf as a trust anchor.
  if ! "$PYTHON" - "${TMP}" <<'PY'
import re, sys, pathlib
d = pathlib.Path(sys.argv[1])
certs = re.findall(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----\n",
                   (d / "chain.pem").read_text(), re.S)
if len(certs) < 2:
    sys.exit("the API server offered %d certificate(s); the CA was not among them -- use -n <node>" % len(certs))
(d / "leaf.pem").write_text(certs[0])
(d / "ca.pem").write_text(certs[-1])
PY
  then
    die "could not separate the certificate chain"
  fi

  openssl verify -CAfile "${TMP}/ca.pem" "${TMP}/leaf.pem" >/dev/null 2>&1 \
    || die "the API server's certificate does not verify against the CA it offered -- do not trust this connection"
fi

openssl x509 -in "${TMP}/ca.pem" -noout -text 2>/dev/null | grep -q "CA:TRUE" \
  || die "the certificate obtained is not a CA"

FINGERPRINT="$(openssl x509 -in "${TMP}/ca.pem" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)"

mkdir -p "$(dirname "$OUT")" || die "cannot create $(dirname "$OUT")"

if ! "$PYTHON" - "${TMP}/ca.pem" "$OUT" "$SERVER" "$ISSUER" "$CLIENT_ID" <<'PY'
import base64, os, pathlib, stat, sys, yaml

ca_pem, out, server, issuer, client_id = sys.argv[1:6]
ca = base64.b64encode(pathlib.Path(ca_pem).read_bytes()).decode()

cfg = {
    "apiVersion": "v1",
    "kind": "Config",
    "current-context": "ankhmorpork",
    "clusters": [{"name": "ankhmorpork",
                  "cluster": {"server": server, "certificate-authority-data": ca}}],
    "users": [{"name": "pocket-id", "user": {"exec": {
        "apiVersion": "client.authentication.k8s.io/v1",
        "command": "kubectl",
        "args": ["oidc-login", "get-token",
                 f"--oidc-issuer-url={issuer}",
                 f"--oidc-client-id={client_id}",
                 "--oidc-extra-scope=email",
                 "--oidc-extra-scope=groups",
                 "--oidc-extra-scope=offline_access",
                 "--oidc-pkce-method=S256"],
        "interactiveMode": "IfAvailable",
        "provideClusterInfo": False,
    }}}],
    "contexts": [{"name": "ankhmorpork",
                  "context": {"cluster": "ankhmorpork", "user": "pocket-id"}}],
    "preferences": {},
}

fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, stat.S_IRUSR | stat.S_IWUSR)
with os.fdopen(fd, "w") as f:
    yaml.safe_dump(cfg, f, sort_keys=False, default_flow_style=False)
PY
then
  die "failed to write $OUT"
fi

echo
echo "Wrote ${OUT}"
echo "  server      ${SERVER}"
echo "  issuer      ${ISSUER}"
echo "  CA SHA-256  ${FINGERPRINT}"
if [ -z "$NODE" ]; then
  echo
  echo "Confirm that fingerprint with someone who already has cluster access"
  echo "before using this on a network you do not control."
fi

if [ "$VERIFY" -eq 1 ]; then
  command -v kubectl >/dev/null || { echo; echo "kubectl not found; skipping verification."; exit 0; }
  kubectl oidc-login --help >/dev/null 2>&1 \
    || { echo; echo "The oidc-login plugin is missing: kubectl krew install oidc-login"; exit 1; }
  echo
  echo "Verifying (a browser will open for the passkey)..."
  KUBECONFIG="$OUT" kubectl auth whoami
fi
