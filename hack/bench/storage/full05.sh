#!/usr/bin/env bash
# Two passes, strictly sequential -- they must never overlap, because all three
# local classes share a volume group per node and concurrent runs would measure
# each other.
#
#   buffered : 15 targets incl. unifi-nas. The honest mode for NFS, and how
#              applications actually use every one of these classes.
#   O_DIRECT : 12 targets, unifi-nas skipped. Page cache out of the way, so the
#              local classes are strictly comparable. NFS is excluded because
#              O_DIRECT turns each write into its own synchronous round trip,
#              which no application does and which measures the test, not the NAS.
#
# Each pass retries with --resume on an outright failure; --resume keeps
# completed cycles and reuses volumes whose layout finished.
cd "$(dirname "$0")" || exit 1
CYCLES="${1:-6}"

run_pass() {
  local id="$1"; shift
  for attempt in 1 2 3 4 5 6; do
    echo "=== $id attempt $attempt at $(date -u +%H:%M:%SZ) ==="
    if [[ $attempt -eq 1 ]] && ! ls -d "results/${id}"-* >/dev/null 2>&1; then
      ./run.sh --cycles "$CYCLES" --runtime 20 --settle 15 --run-id "$id" "$@" && return 0
    else
      ./run.sh --cycles "$CYCLES" --runtime 20 --settle 15 --resume "$id" "$@" && return 0
    fi
    echo "=== $id exited $?, retrying in 120s ==="
    sleep 120
  done
  echo "=== $id gave up after 6 attempts ==="
  return 1
}

echo "########## PASS 1/2: buffered, 15 targets ##########"
run_pass buf05 --buffered
echo "########## PASS 2/2: O_DIRECT, 12 targets ##########"
run_pass dir05 --skip unifi-nas
echo "########## both passes finished at $(date -u +%H:%M:%SZ) ##########"
