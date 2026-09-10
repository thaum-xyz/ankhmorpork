#!/bin/sh
# Assemble the kubeconfig from what the API server is actually running on,
# rather than from a copy of it kept anywhere else.
#
#   issuer, client ID  /etc/rancher/k3s/authentication-config.yaml
#   API server address /etc/rancher/k3s/config.yaml (tls-san)
#   cluster CA         the kube-root-ca.crt ConfigMap, which the control
#                      plane maintains in every namespace
#
# Fails closed. A missing file or an empty value aborts, the pod never
# becomes ready and nginx serves nothing -- publishing a subtly wrong
# kubeconfig is worse than publishing none, because a wrong CA is a trust
# failure and a wrong audience is a login that breaks at the user.
set -eu

auth=/node/authentication-config.yaml
conf=/node/config.yaml
ca=/ca/ca.crt

fail() { echo "kubeconfig-builder: $*" >&2; exit 1; }

[ -r "$auth" ] || fail "cannot read $auth"
[ -r "$conf" ] || fail "cannot read $conf"
[ -s "$ca" ]   || fail "$ca is missing or empty"

# The audience is the OIDC client ID: the apiserver rejects a token whose
# aud does not appear here, so this is the value the kubeconfig must carry.
ISSUER=$(yq -r '.jwt[0].issuer.url // ""' "$auth")
CLIENT_ID=$(yq -r '.jwt[0].issuer.audiences[0] // ""' "$auth")
VIP=$(yq -r '.["tls-san"][0] // ""' "$conf")

[ -n "$ISSUER" ]    || fail "no .jwt[0].issuer.url in $auth"
[ -n "$CLIENT_ID" ] || fail "no .jwt[0].issuer.audiences[0] in $auth"
[ -n "$VIP" ]       || fail "no .tls-san[0] in $conf"

SERVER="https://${VIP}:6443"
export SERVER ISSUER CLIENT_ID CA_FILE="$ca"

yq '
  .clusters[0].cluster.server = strenv(SERVER) |
  .clusters[0].cluster."certificate-authority-data" = (load_str(strenv(CA_FILE)) | @base64) |
  .users[0].user.exec.args[] |= sub("ISSUER_PLACEHOLDER", strenv(ISSUER)) |
  .users[0].user.exec.args[] |= sub("CLIENT_ID_PLACEHOLDER", strenv(CLIENT_ID))
' /builder/kubeconfig.yaml > /out/kubeconfig

! grep -q PLACEHOLDER /out/kubeconfig || fail "a placeholder survived substitution"

# World-readable on purpose: nginx runs as another uid, and nothing in this
# file is secret. The server address and the OIDC client ID are public by
# design, and the API server hands the CA to every anonymous TLS client.
chmod 0644 /out/kubeconfig
echo "kubeconfig-builder: server=${SERVER} issuer=${ISSUER}"
