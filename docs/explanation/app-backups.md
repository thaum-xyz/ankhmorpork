# How app backups are shaped { .quad-explanation }

Every namespace that backs itself up carries the same pair of objects, a
`PersistentVolumeClaim` called `backup-repo` and a K8up `Schedule` called
`backup`, under `k8s/apps/<app>/backup/`. They differ only in their timetable.
The shape is one set of decisions, recorded here once; the copies carry the
times and nothing else.

Which claims in the namespace are backed up is decided per claim, by the
[`k8up.io/backup`](../reference/annotations.md#k8upiobackup) annotation.

## The decisions

| Decision | Setting | Why |
| --- | --- | --- |
| One restic repository per namespace | a `backup-repo` claim on `unifi-nas` in each namespace | a corrupted repository costs one namespace; `restic check` stays cheap; and two backups never contend for one repository lock over an NFSv3 mount with `nolock` |
| Plain restic files on the NAS, not S3 | `backend.local` on that claim, no versitygw | versitygw's posix backend would write the same files to the same export; going direct means a restore needs restic and an NFS mount, with no cluster running |
| One repository password for the fleet | no `repoPasswordSecretRef` | the operator supplies `RESTIC_PASSWORD` from `BACKUP_GLOBALREPOPASSWORD`, set once in the k8up component; a per-Schedule reference would override it for that namespace alone |
| Backup Pods run as root | `podSecurityContext` uid and gid `0` | csi-nfs creates each subdirectory `0775` owned by `977:988` and the UNAS refuses `chown`, so `fsGroup` cannot fix it and a non-root Pod cannot write its own repository, as measured on a live claim with a uid 1000 Pod. A backup agent also has to read every file it is pointed at, whoever owns it |
| Fixed times, a quarter of an hour apart | `backup.schedule` per namespace, never `@daily-random` | a restic repository is only consistent at rest, so the off-site copy of the export needs a known quiet window: everything finishes before 01:30 UTC, when the UNAS ships its shares off-site, and sits clear of the Postgres backups and paperless's own export in the table below |
| Check weekly, prune after check | `check` on Sunday morning, `prune` ninety minutes later | a repository that already fails verification is not repacked before anyone has seen the failure; the operator also runs one prune at a time, because prune rewrites pack files |
| Retention | 14 daily, 8 weekly, 6 monthly | |
| No `excluded_from_alerts` label by hand | nothing on the claim | `mutate-nfs-pvc-alert-exclusion` stamps every `unifi-nas` claim; see [`excluded_from_alerts`](../reference/annotations.md#excluded_from_alerts) |

The fleet-wide settings sit with the operator in
[`k8s/platform/storage/k8up/values.yaml`](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/platform/storage/k8up/values.yaml):
the shared password, the limit of two concurrent backup jobs the 1GbE link to
the UNAS imposes, and the one-prune-at-a-time rule.

## The timetable

Everything that writes a backup to the UNAS at night, read from the manifests:
the K8up Schedules, the CloudNativePG backups each `cnpg-database` release
schedules, and paperless's own export. Times are UTC. A new namespace's backup
goes into a free quarter hour here, before the 01:30 UTC deadline.

<!-- generated:backup-timetable -->
<!-- This block is written by hack/generate-docs-reference.py; edit the
     manifests it reads, not the table. -->
| When | Namespace | What | Check | Prune | Retention |
| --- | --- | --- | --- | --- | --- |
| [21:15](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/apps/mealie/backup/schedule.yaml) | `mealie` | K8up `Schedule` | `45 5 * * 0` | `15 7 * * 0` | 14 daily, 8 weekly, 6 monthly |
| [21:30](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/apps/changedetection/backup/schedule.yaml) | `changedetection` | K8up `Schedule` | `0 6 * * 0` | `30 7 * * 0` | 14 daily, 8 weekly, 6 monthly |
| [21:45](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/apps/karakeep/backup/schedule.yaml) | `karakeep` | K8up `Schedule` | `15 6 * * 0` | `45 7 * * 0` | 14 daily, 8 weekly, 6 monthly |
| [22:00](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/apps/mended-drum/backup/schedule.yaml) | `mended-drum` | K8up `Schedule` | `30 6 * * 0` | `0 8 * * 0` | 14 daily, 8 weekly, 6 monthly |
| [22:15](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/apps/vod-arr/backup/schedule.yaml) | `vod-arr` | K8up `Schedule` | `45 6 * * 0` | `15 8 * * 0` | 14 daily, 8 weekly, 6 monthly |
| [22:36](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/apps/paperless/manifests/backups/cronjob.yaml) | `paperless` | CronJob `paperless-backup` | — | — | — |
| [22:36](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/apps/paperless/manifests/postgres/values.yaml) | `paperless` | CloudNativePG `postgres` | — | — | 14d |
| [23:17](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/apps/atuin/postgres/values.yaml) | `atuin` | CloudNativePG `postgres` | — | — | 14d |
| [23:17](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/apps/grafana/postgres/values.yaml) | `grafana` | CloudNativePG `postgres` | — | — | 3d |
| [23:17](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/apps/mealie/db/values.yaml) | `mealie` | CloudNativePG `postgres` | — | — | 30d |
| [23:17](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/apps/pocket-id/postgres/values.yaml) | `pocket-id` | CloudNativePG `postgres` | — | — | 30d |
| [23:30](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/apps/ai-gateway/db/values.yaml) | `ai-gateway` | CloudNativePG `postgres` | — | — | 30d |
| [23:30](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/apps/mended-drum/db/values.yaml) | `mended-drum` | CloudNativePG `postgres` | — | — | 30d |
| [23:43](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/apps/photos/db/values.yaml) | `photos` | CloudNativePG `postgres` | — | — | 14d |
| [23:57](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/apps/vod-arr/sonarrdb/values.yaml) | `vod-arr` | CloudNativePG `postgres-sonarr` | — | — | 7d |
| [00:07](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/apps/vod-arr/radarrdb/values.yaml) | `vod-arr` | CloudNativePG `postgres-radarr` | — | — | 7d |
| [00:17](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/apps/vod-arr/prowlarrdb/values.yaml) | `vod-arr` | CloudNativePG `postgres-prowlarr` | — | — | 7d |
| [00:27](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/apps/vod-arr/seerrdb/values.yaml) | `vod-arr` | CloudNativePG `postgres-seerr` | — | — | 7d |
| [00:37](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/apps/vod-arr/bazarrdb/values.yaml) | `vod-arr` | CloudNativePG `postgres-bazarr` | — | — | 7d |
<!-- /generated:backup-timetable -->
