#!/usr/bin/env bash
# Serial StorageClass benchmark for the ankhmorpork cluster.
#
# Runs exactly one target at a time. That is not politeness: lvm-thin,
# piraeus-r2 and longhorn on a given node all sit on the same volume group, so
# two concurrent targets would be measuring each other.
#
# Usage:
#   ./run.sh                          # all targets in targets.env
#   ./run.sh --only lvm-thin          # filter by class or node substring
#   ./run.sh --resume <run-id>        # continue a run, skipping finished targets
#   ./run.sh --only unifi-nas --buffered   # NFS as an app actually uses it
#   ./run.sh --dry-run                # print the plan, touch nothing
#
# Needs kubectl and jq. report.py, which it runs at the end, needs python3.
set -euo pipefail

cd "$(dirname "$0")"

: "${KUBECONFIG:=$HOME/.kube/clusters/ankhmorpork}"
export KUBECONFIG

PROFILE=modern
FIO_IMAGE="docker.io/library/alpine:3.24.1"
VOLUME_SIZE=16Gi
FIO_SIZE=8G
FIO_DIRECT=1
FIO_OFFSET_INCREMENT=500M
RUNTIME=45
SETTLE=45
JOB_TIMEOUT=1800
ONLY=""
SKIP=""
DRY_RUN=false
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RESUME=false
# Repeat passes over the whole target list. On a live cluster a single pass
# measures each target under whatever load happened to exist in its slot; three
# interleaved passes spread that noise across all targets instead of pinning it
# to one. report.py takes the median and reports the spread.
CYCLES=3
# Where the hostpath baseline writes. Beside Longhorn's replicas/ directory,
# never inside it.
HOSTPATH_DIR="/var/lib/rancher/longhorn/storage-bench-scratch"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --only) ONLY="$2"; shift 2 ;;
    --skip) SKIP="$2"; shift 2 ;;
    --runtime) RUNTIME="$2"; shift 2 ;;
    --fio-size) FIO_SIZE="$2"; shift 2 ;;
    --volume-size) VOLUME_SIZE="$2"; shift 2 ;;
    --settle) SETTLE="$2"; shift 2 ;;
    # O_DIRECT is the default because it is the only way to compare classes
    # without the page cache answering for them. It is also unrepresentative for
    # unifi-nas: direct=1 on NFS turns every write into its own synchronous
    # round trip with no client-side coalescing, which no real application does.
    # Use --buffered for a second NFS run that reflects actual app behaviour.
    --buffered) FIO_DIRECT=0; shift ;;
    --run-id) RUN_ID="$2"; shift 2 ;;
    --resume) RUN_ID="$2"; RESUME=true; shift 2 ;;
    --cycles) CYCLES="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

SUFFIX=""
[[ "$FIO_DIRECT" == "0" ]] && SUFFIX="-buffered"
OUT="results/${RUN_ID}-${PROFILE}${SUFFIX}"
log()  { printf '%s  %s\n' "$(date -u +%H:%M:%S)" "$*"; }
fail() { printf '%s  ERROR: %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

render() {
  # Deliberately not envsubst: it is not installed everywhere, and the template
  # set is small and fully known.
  sed -e "s|\${PVC_NAME}|${PVC_NAME}|g" \
      -e "s|\${JOB_NAME}|${JOB_NAME}|g" \
      -e "s|\${TARGET_ID}|${TARGET_ID}|g" \
      -e "s|\${SC}|${SC}|g" \
      -e "s|\${NODE}|${NODE}|g" \
      -e "s|\${VOLUME_SIZE}|${VOLUME_SIZE}|g" \
      -e "s|\${FIO_IMAGE}|${FIO_IMAGE}|g" \
      -e "s|\${FIO_SIZE}|${FIO_SIZE}|g" \
      -e "s|\${FIO_DIRECT}|${FIO_DIRECT}|g" \
      -e "s|\${FIO_OFFSET_INCREMENT}|${FIO_OFFSET_INCREMENT}|g" \
      -e "s|\${RUNTIME}|${RUNTIME}|g" \
      -e "s|\${PROFILE}|${PROFILE}|g" \
      -e "s|\${HOSTPATH}|${HOSTPATH_DIR}|g" \
      "$1"
}

# --- target list -------------------------------------------------------------
# Built with a read loop rather than mapfile: macOS ships bash 3.2, where
# mapfile does not exist, and this script is run from a laptop.
TARGETS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && TARGETS+=("$line")
done < <(grep -vE '^[[:space:]]*(#|$)' targets.env \
         | awk '{print $1" "$2}' \
         | { if [[ -n "$ONLY" ]]; then grep -- "$ONLY" || true; else cat; fi; } \
         | { if [[ -n "$SKIP" ]]; then grep -v -- "$SKIP" || true; else cat; fi; })

[[ ${#TARGETS[@]} -gt 0 ]] || { fail "no targets selected"; exit 1; }

echo
echo "run id     : $RUN_ID"
echo "profile    : $PROFILE  (runtime ${RUNTIME}s/job, file $FIO_SIZE, volume $VOLUME_SIZE)"
echo "io mode    : $([[ "$FIO_DIRECT" == "1" ]] && echo 'O_DIRECT' || echo 'buffered (page cache in play)')"
echo "targets    : ${#TARGETS[@]}  x ${CYCLES} interleaved cycle(s)"
printf '             %s\n' "${TARGETS[@]}"
echo "output     : $OUT"
echo "kubeconfig : $KUBECONFIG"
echo

if $DRY_RUN; then echo "dry run, stopping here"; exit 0; fi

kubectl version --request-timeout=10s -o json >/dev/null || { fail "cluster unreachable"; exit 1; }
mkdir -p "$OUT"

# --- one-time setup ---------------------------------------------------------
kubectl apply -f manifests/namespace.yaml >/dev/null
kubectl -n bench create configmap storage-bench-scripts \
  --from-file=entrypoint.sh=manifests/entrypoint.sh \
  --from-file=modern.fio=fio/modern.fio \
  --from-file=precondition.fio=fio/precondition.fio \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
log "namespace + scripts configmap ready"

# Record the environment the numbers were produced in. Without this a results
# directory is uninterpretable six months later.
{
  echo "run_id: $RUN_ID"
  echo "profile: $PROFILE"
  echo "fio_size: $FIO_SIZE"
  echo "volume_size: $VOLUME_SIZE"
  echo "runtime_per_job: ${RUNTIME}s"
  echo "fio_direct: $FIO_DIRECT"
  echo "io_mode: $([[ "$FIO_DIRECT" == "1" ]] && echo o_direct || echo buffered)"
  echo "image: $FIO_IMAGE"
} > "$OUT/run-metadata.yaml"
kubectl get nodes -o wide            > "$OUT/env-nodes.txt" 2>&1 || true
kubectl get sc -o yaml               > "$OUT/env-storageclasses.yaml" 2>&1 || true
kubectl get nodes.longhorn.io -n longhorn-system -o wide \
                                     > "$OUT/env-longhorn-nodes.txt" 2>&1 || true


# --- connectivity resilience -------------------------------------------------
# A 10-cycle run takes many hours over a laptop-to-cluster link, so a dropped
# connection is expected rather than exceptional. Nothing below treats a failed
# kubectl as a failed target: the fio work runs as Kubernetes Jobs and keeps
# going regardless of whether this laptop can see it.

# Retry a kubectl invocation through transient API/network errors.
k() {
  local tries=0 out rc
  while :; do
    out="$(kubectl "$@" 2>&1)"; rc=$?
    [[ $rc -eq 0 ]] && { printf '%s' "$out"; return 0; }
    # A genuine "not found" is an answer, not a network problem.
    if [[ "$out" == *"NotFound"* || "$out" == *"not found"* ]]; then
      printf '%s' "$out"; return $rc
    fi
    tries=$((tries+1))
    if [[ $tries -ge 5 ]]; then printf '%s' "$out"; return $rc; fi
    sleep $((tries*5))
  done
}

# Block until the API answers again. Returns 1 only after ~30 minutes.
wait_cluster() {
  local waited=0
  while ! kubectl version --request-timeout=10s -o json >/dev/null 2>&1; do
    if [[ $waited -eq 0 ]]; then fail "  cluster unreachable, waiting for it to come back"; fi
    sleep 20; waited=$((waited+20))
    if [[ $waited -ge 5400 ]]; then fail "  cluster still unreachable after 90m"; return 1; fi
  done
  if [[ $waited -gt 0 ]]; then log "  cluster reachable again after ${waited}s"; fi
  return 0
}

# Poll a Job to completion. Unlike `kubectl wait`, a failed poll is retried
# rather than being mistaken for the Job failing -- which would delete a Job
# that is still doing useful work.
#   0 = succeeded, 1 = failed, 2 = timed out
wait_job() {
  local job="$1" timeout="$2" start=$SECONDS s f
  while (( SECONDS - start < timeout )); do
    if ! wait_cluster; then return 2; fi
    s="$(kubectl -n bench get job "$job" -o jsonpath='{.status.succeeded}' 2>/dev/null)" || { sleep 15; continue; }
    [[ "$s" == "1" ]] && return 0
    f="$(kubectl -n bench get job "$job" -o jsonpath='{.status.failed}' 2>/dev/null)" || true
    [[ -n "$f" && "$f" != "0" ]] && return 1
    sleep 15
  done
  return 2
}

# Wait for a PVC to bind, tolerating connectivity loss the same way.
wait_bound() {
  local pvc="$1" timeout="$2" start=$SECONDS ph
  while (( SECONDS - start < timeout )); do
    if ! wait_cluster; then return 1; fi
    ph="$(kubectl -n bench get pvc "$pvc" -o jsonpath='{.status.phase}' 2>/dev/null)" || { sleep 10; continue; }
    [[ "$ph" == "Bound" ]] && return 0
    sleep 10
  done
  return 1
}

cleanup_job() {
  kubectl -n bench delete job "$1" --ignore-not-found --wait=true --timeout=120s >/dev/null 2>&1 || true
}

cleanup_target() {
  local pvc="$1" job="$2"
  kubectl -n bench delete job "$job" --ignore-not-found --wait=true --timeout=120s >/dev/null 2>&1 || true
  local pv
  pv="$(kubectl -n bench get pvc "$pvc" -o jsonpath='{.spec.volumeName}' 2>/dev/null || true)"
  kubectl -n bench delete pvc "$pvc" --ignore-not-found --wait=true --timeout=300s >/dev/null 2>&1 || true
  if [[ -n "$pv" ]]; then
    # Reclaim must finish before the next target starts, or the next run competes
    # with a background delete on the same thin pool.
    for _ in $(seq 1 60); do
      kubectl get pv "$pv" >/dev/null 2>&1 || break
      sleep 5
    done
  fi
}

# --- phase 1: provision and precondition ------------------------------------
# Volumes are laid out once and kept for every cycle. Preconditioning an 8GiB
# file costs ~150s on longhorn, so paying it per cycle is what previously made
# repeated sampling unaffordable.
FAILED=()
set +u  # bash 3.2 treats an empty array as unbound under set -u
LIVE=()

i=0
for target in "${TARGETS[@]}"; do
  i=$((i+1))
  SC="${target%% *}"; NODE="${target##* }"
  IS_HOSTPATH=false; [[ "$SC" == hostpath-* ]] && IS_HOSTPATH=true
  TARGET_ID="${SC}-${NODE}"
  PVC_NAME="bench-${TARGET_ID}"; JOB_NAME="prep-${TARGET_ID}"
  TDIR="$OUT/$TARGET_ID"; mkdir -p "$TDIR"

  echo
  log "[prep $i/${#TARGETS[@]}] $SC on $NODE"
  cleanup_job "$JOB_NAME"

  # On resume, a Bound PVC from the interrupted attempt is already
  # preconditioned; recreating it would throw away ~25 minutes of layout work
  # across the matrix for nothing.
  # Bound is NOT the same as preconditioned: a volume whose layout job was
  # interrupted binds fine but is only partly allocated, and reads of
  # unallocated blocks come back at fake speed. Reuse only volumes whose layout
  # actually finished, recorded by the marker written below.
  if $RESUME && ! $IS_HOSTPATH && [[ -f "$TDIR/.preconditioned" ]] \
     && [[ "$(kubectl -n bench get pvc "$PVC_NAME" -o jsonpath='{.status.phase}' 2>/dev/null)" == "Bound" ]]; then
    log "  volume already provisioned and preconditioned, reusing"
    LIVE+=("$target")
    continue
  fi

  if $IS_HOSTPATH; then
    PROFILE=precondition render manifests/job-hostpath.yaml.tpl > "$TDIR/prep.yaml"
  else
    kubectl -n bench delete pvc "$PVC_NAME" --ignore-not-found --wait=true --timeout=300s >/dev/null 2>&1
    render manifests/pvc.yaml.tpl > "$TDIR/pvc.yaml"
    kubectl apply -f "$TDIR/pvc.yaml" >/dev/null
    PROFILE=precondition render manifests/job.yaml.tpl > "$TDIR/prep.yaml"
  fi
  kubectl apply -f "$TDIR/prep.yaml" >/dev/null

  if ! $IS_HOSTPATH && ! wait_bound "$PVC_NAME" 600; then
    fail "  pvc never bound"
    kubectl -n bench describe pvc "$PVC_NAME" > "$TDIR/pvc-describe.txt" 2>&1 || true
    FAILED+=("$TARGET_ID (pvc unbound)"); cleanup_job "$JOB_NAME"; continue
  fi

  if ! $IS_HOSTPATH; then
    PV="$(kubectl -n bench get pvc "$PVC_NAME" -o jsonpath='{.spec.volumeName}')"
    kubectl get pv "$PV" -o yaml > "$TDIR/pv-live.yaml" 2>&1 || true
    case "$SC" in
      longhorn|longhorn-*)
        for _ in $(seq 1 60); do
          r="$(kubectl -n longhorn-system get volumes.longhorn.io "$PV" \
                -o jsonpath='{.status.robustness}' 2>/dev/null || true)"
          [[ "$r" == "healthy" ]] && break; sleep 5
        done
        log "  longhorn robustness=${r:-unknown}"
        kubectl -n longhorn-system get replicas.longhorn.io -l "longhornvolume=$PV" \
          -o wide > "$TDIR/longhorn-replicas.txt" 2>&1 || true ;;
      piraeus-*)
        kubectl get volumeattachments -o wide 2>/dev/null | grep -- "$PV" \
          > "$TDIR/volumeattachment.txt" 2>&1 || true
        # Which state was measured matters most for the roaming class: a Pod can
        # attach diskless and run fully remote until auto-diskful converts it.
        # Without this the two states are indistinguishable in the results.
        LC=$(kubectl -n platform-storage get pods -l app.kubernetes.io/component=linstor-controller \
               -o name 2>/dev/null | head -1)
        if [[ -n "$LC" ]]; then
          kubectl -n platform-storage exec "$LC" -- linstor resource list-volumes 2>/dev/null \
            | grep -- "$PV" > "$TDIR/linstor-placement.txt" 2>&1 || true
          if grep -qi "diskless" "$TDIR/linstor-placement.txt" 2>/dev/null; then
            log "  NOTE: $NODE holds a DISKLESS attachment -- measuring remote I/O"
          fi
        fi ;;
    esac
  fi

  if wait_job "$JOB_NAME" "$JOB_TIMEOUT"; then
    log "  preconditioned"
    touch "$TDIR/.preconditioned"
    LIVE+=("$target")
  else
    fail "  preconditioning did not complete"
    rm -f "$TDIR/.preconditioned"
    kubectl -n bench logs "job/$JOB_NAME" --tail=40 > "$TDIR/prep.log" 2>&1 || true
    FAILED+=("$TARGET_ID (precondition)")
  fi
  cleanup_job "$JOB_NAME"
done

[[ ${#LIVE[@]} -gt 0 ]] || { fail "nothing preconditioned successfully"; exit 1; }

# --- phase 2: interleaved measurement cycles --------------------------------
for cyc in $(seq 1 "$CYCLES"); do
  echo
  log "########## cycle $cyc of $CYCLES ##########"
  j=0
  for target in "${LIVE[@]}"; do
    j=$((j+1))
    SC="${target%% *}"; NODE="${target##* }"
    IS_HOSTPATH=false; [[ "$SC" == hostpath-* ]] && IS_HOSTPATH=true
    TARGET_ID="${SC}-${NODE}"
    PVC_NAME="bench-${TARGET_ID}"; JOB_NAME="run${cyc}-${TARGET_ID}"
    CDIR="$OUT/$TARGET_ID/cycle-$cyc"; mkdir -p "$CDIR"

    if $RESUME && [[ -s "$CDIR/fio.json" ]] \
       && jq -e . "$CDIR/fio.json" >/dev/null 2>&1; then
      log "  [$j/${#LIVE[@]}] $TARGET_ID already measured, skipping"; continue
    fi

    cleanup_job "$JOB_NAME"
    if $IS_HOSTPATH; then render manifests/job-hostpath.yaml.tpl > "$CDIR/job.yaml"
    else render manifests/job.yaml.tpl > "$CDIR/job.yaml"; fi
    kubectl apply -f "$CDIR/job.yaml" >/dev/null

    if wait_job "$JOB_NAME" "$JOB_TIMEOUT"; then
      # Logs can fail on a blip even though the Job succeeded; retry before
      # concluding the measurement was lost.
      for _ in 1 2 3; do
        kubectl -n bench logs "job/$JOB_NAME" --tail=-1 > "$CDIR/pod.log" 2>&1 && break
        sleep 10
      done
      sed -n '/-----BEGIN FIO JSON-----/,/-----END FIO JSON-----/p' "$CDIR/pod.log" \
        | sed '1d;$d' > "$CDIR/fio.json" || true
      if [[ -s "$CDIR/fio.json" ]] && jq -e . "$CDIR/fio.json" >/dev/null 2>&1; then
        log "  [$j/${#LIVE[@]}] $TARGET_ID ok"
      else
        fail "  [$j/${#LIVE[@]}] $TARGET_ID produced no valid json"
        rm -f "$CDIR/fio.json"; FAILED+=("$TARGET_ID cycle$cyc (no json)")
      fi
    else
      fail "  [$j/${#LIVE[@]}] $TARGET_ID job did not complete"
      kubectl -n bench logs "job/$JOB_NAME" --tail=40 > "$CDIR/pod.log" 2>&1 || true
      FAILED+=("$TARGET_ID cycle$cyc (job)")
    fi
    cleanup_job "$JOB_NAME"
    sleep "$SETTLE"
  done
done

# --- phase 3: teardown -------------------------------------------------------
echo
log "tearing down volumes"
for target in "${TARGETS[@]}"; do
  SC="${target%% *}"; NODE="${target##* }"
  [[ "$SC" == hostpath-* ]] && continue
  cleanup_target "bench-${SC}-${NODE}" "unused"
done

echo
log "all targets done"
if [[ ${#FAILED[@]} -gt 0 ]]; then
  fail "${#FAILED[@]} target(s) had problems:"
  printf '         - %s\n' "${FAILED[@]}" >&2
fi

echo
log "building report"
python3 report.py "$OUT" || fail "report generation failed"
echo
echo "results: $OUT"
echo "report : $OUT/summary.md"
echo
echo "Thin pools do not return space to the VG until the blocks are discarded."
echo "Run hack/lvm-trim.sh on the tested nodes if 'vgs' looks fuller than expected."
