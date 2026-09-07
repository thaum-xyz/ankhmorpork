#!/bin/sh
# Runs inside the fio pod. Installs fio, renders the profile, emits JSON between
# markers so run.sh can lift it straight out of `kubectl logs`.
set -eu

if ! command -v fio >/dev/null 2>&1; then
  echo ">> installing fio"
  apk add --no-cache fio >/dev/null 2>&1 || {
    echo "FATAL: could not install fio (no egress from this pod?)" >&2
    exit 1
  }
fi

fio --version
echo ">> mount: $(df -hT "$MOUNT" | tail -1)"
echo ">> profile: $PROFILE  size=$FIO_SIZE direct=$FIO_DIRECT runtime=${RUNTIME}s"

# fio expands ${VAR} in a job file from the environment.
fio --output-format=json+ \
    --output=/tmp/result.json \
    --eta=never \
    "/scripts/${PROFILE}.fio"

echo "-----BEGIN FIO JSON-----"
cat /tmp/result.json
echo "-----END FIO JSON-----"

rm -f "$MOUNT/fiotest"
echo ">> done"
