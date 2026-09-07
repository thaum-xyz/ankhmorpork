# seerr: SQLite to postgres-seerr

One-off cutover for [#1370](https://github.com/thaum-xyz/ankhmorpork/issues/1370).
A Job runs pgloader against the SQLite file on `seerr-config` and copies the
rows into the `postgres-seerr` cluster. It lives here and not under `k8s/`
because Flux must never apply it: it truncates seerr's tables first.

Rehearsed on 2026-09-07 against `postgres:17` and `seerr:v3.4.1` with a copy of
the live file: 793 rows over 14 tables, foreign keys dropped and recreated by
pgloader, sequences reset, schema byte-identical to one seerr created itself,
seerr serving every request and user through its API afterwards, and a second
run over a WAL-mode copy with a pending `-wal` loading cleanly.

## Before

- Doppler holds `SEERR_DB_ADMIN_PASS` and `SEERR_DB_PASS`, and both
  `postgres-seerr-*` ExternalSecrets are `SecretSynced`.
- `postgres-seerr` reports `Cluster in healthy state`.
- barman has written to the new store once. The first scheduled backup is at
  03:57 and the chart's `CNPGBackupMissing` goes critical after six hours
  without one, so take one by hand as soon as the cluster is healthy. It also
  proves the object store path before anything depends on it:

```bash
kubectl cnpg backup postgres-seerr -n vod-arr -m plugin --plugin-name barman-cloud.cloudnative-pg.io
```
- seerr has started against it once, so the schema exists. The Deployment in
  `k8s/apps/vod-arr/seerr` points at it; a running pod is the evidence:

```bash
kubectl -n vod-arr exec deploy/seerr -- sh -c 'env | grep ^DB_TYPE'
```

## Steps

1. Hold Flux off the namespace so the scale-down below is not undone:

    ```bash
    flux -n flux-system suspend kustomization vod-arr
    ```

2. Stop seerr. It closes its SQLite connection on the way out; a `-wal` left
   behind is fine, the Job mounts the claim read-write for exactly that case.

    ```bash
    kubectl -n vod-arr scale deployment seerr --replicas=0 && kubectl -n vod-arr wait --for=delete pod -l app.kubernetes.io/name=seerr --timeout=2m
    ```

3. Run the load:

    ```bash
    kubectl apply -k hack/seerr-sqlite-to-postgres && kubectl -n vod-arr wait --for=condition=complete job/seerr-sqlite-to-postgres --timeout=5m
    ```

4. Read the summary. Every table must show `errors 0` and `read` equal to
   `imported`; `media_request` must match what the SQLite file held (28 when
   the issue was filed).

    ```bash
    kubectl -n vod-arr logs job/seerr-sqlite-to-postgres | tail -30
    ```

5. Start seerr and hand the namespace back to Flux:

    ```bash
    kubectl -n vod-arr scale deployment seerr --replicas=1 && kubectl -n vod-arr rollout status deployment seerr && flux -n flux-system resume kustomization vod-arr
    ```

6. Sign in at <https://seek.krupa.net.pl> and open the request list. Then drop
   the Job:

    ```bash
    kubectl delete -k hack/seerr-sqlite-to-postgres
    ```

7. The SQLite file stays on the claim as the fallback until the first
   *scheduled* backup after the cutover has completed, which proves the
   schedule and not just the hand-taken one:

    ```bash
    kubectl -n vod-arr get backups.postgresql.cnpg.io -l cnpg.io/cluster=postgres-seerr
    ```

   Once one is `completed`, remove the old database from the running pod:

    ```bash
    kubectl -n vod-arr exec deploy/seerr -- rm -r /app/config/db
    ```

## If it fails

The Job truncates before it copies, so fixing the cause and re-applying is
safe for as long as seerr stays at zero replicas. pgloader only reads the
SQLite file (it checkpoints the WAL on close, nothing more), so reverting the
Deployment change puts seerr back on it unchanged.
