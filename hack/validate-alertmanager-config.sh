#!/bin/bash

# Renders the Alertmanager configuration the way external-secrets will, and
# checks the result with amtool.
#
# The config reaches the cluster as a Go template in the `alertmanager.yaml` key
# of a ConfigMap, which ESO renders into a Secret. Every other check in this
# repo therefore only ever sees a ConfigMap holding an opaque string: an
# undefined receiver, a route naming a time interval that does not exist, or a
# timezone Go cannot load all render and pass kubeconform, then fail at the
# Alertmanager end, where the only symptom is AlertmanagerFailedReload.
#
# esoctl does the rendering because it is ESO's own engine. Two kinds of {{ }}
# share that file -- ESO secret references, and Alertmanager's own notification
# templates escaped as {{ `{{ ... }}` }} so ESO leaves them alone -- and
# anything reimplementing that split here is a second implementation to keep in
# step with the first.
#
# Verified to catch: YAML that does not parse, a route naming a receiver or a
# time interval that does not exist, and an unloadable timezone. It does NOT
# compile the receivers' notification templates, so an unclosed {{ in an
# opsgenie description passes here and fails at notify time.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

dir=k8s/apps/datalake-alerts/alertmanager
es=$dir/externalsecret.yaml
cm=$dir/configmap-template.yaml
am=$dir/alertmanager.yaml

missing=0
for tool in yq esoctl amtool; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "  $tool not found"
    missing=1
  fi
done
if [ "$missing" -ne 0 ]; then
  echo "  install with:"
  echo "    go install github.com/mikefarah/yq/v4@latest"
  # esoctl has no go.mod of its own and the parent module carries replace
  # directives, so `go install pkg@version` refuses it and there are no
  # published binaries. Building from a checkout is the only route.
  echo "    git clone --depth 1 https://github.com/external-secrets/external-secrets"
  echo "    (cd external-secrets && go build -o \"\$(go env GOPATH)/bin/esoctl\" ./cmd/esoctl)"
  # amtool's config schema is version-specific, so name the version the cluster
  # actually runs. yq may itself be the missing tool, hence the fallback.
  echo "    go install github.com/prometheus/alertmanager/cmd/amtool@$(yq -r '.spec.version' "$am" 2>/dev/null || echo '<version from '"$am"'>')"
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# esoctl wants the secret's data section, base64 as a Secret carries it. The
# values are credentials and never leave this machine, so any stand-in does --
# but it is URL-shaped for every key, not only the ones holding URLs: amtool
# rejects a bare word where a webhook url belongs, while a field wanting an
# opaque string takes a URL-shaped one happily, so one shape satisfies both.
# .invalid is the RFC 2606 TLD that can never resolve if one ever escapes into
# something that dials it.
{
  printf '{'
  sep=''
  while IFS= read -r key; do
    value=$(printf 'https://placeholder.invalid/%s' "$key" | base64 | tr -d '\n')
    printf '%s"%s":"%s"' "$sep" "$key" "$value"
    sep=','
  done < <(yq -r '.spec.data[].secretKey' "$es")
  printf '}'
} > "$tmp/secret-data.json"

if ! esoctl template \
  --source-templated-object "$es" \
  --template-from-config-map "$cm" \
  --source-secret-data-file "$tmp/secret-data.json" \
  > "$tmp/secret.yaml" 2> "$tmp/esoctl.err"; then
  echo "  esoctl could not render the template:"
  head -6 "$tmp/esoctl.err" | sed 's/^/    /'
  exit 1
fi

yq -r '.data."alertmanager.yaml" // ""' "$tmp/secret.yaml" | base64 -d > "$tmp/alertmanager.yaml" 2>/dev/null

# An ExternalSecret whose defaults are left implicit renders to an empty Secret
# and exits 0: esoctl unmarshals these files directly and applies no CRD
# defaulting, so templateFrom[].target, template.engineVersion and
# items[].templateAs all have to be spelled out in the manifest.
if [ ! -s "$tmp/alertmanager.yaml" ]; then
  echo "  esoctl rendered an empty Secret. Check that $(basename "$es") sets"
  echo "  target, engineVersion and templateAs explicitly."
  exit 1
fi

echo "  rendered by esoctl: $(wc -c < "$tmp/alertmanager.yaml" | tr -d ' ') bytes," \
     "secrets substituted: $(yq -r '[.spec.data[].secretKey] | join(", ")' "$es")"

amtool check-config "$tmp/alertmanager.yaml" > "$tmp/amtool.out" 2>&1
rc=$?
sed -e "s|$tmp/alertmanager.yaml|$cm|g" -e '/^[[:space:]]*$/d' -e 's/^/  /' "$tmp/amtool.out"
if [ "$rc" -ne 0 ]; then
  exit "$rc"
fi

intervals=$(yq -r '[.time_intervals[]?.name] | join(", ")' "$tmp/alertmanager.yaml")
echo "  time intervals defined: ${intervals:-none}"
