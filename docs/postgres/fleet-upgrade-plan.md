# PostgreSQL fleet: state and upgrade plan

Surveyed 2026-08-23. Eleven CNPG clusters on operator 1.30.0, chart
`cnpg-database`.

## Why the fleet is scattered

Nine clusters never set `imageName`. CloudNativePG defaults it at creation and
**writes that value into the spec permanently** — it does not re-default when the
operator is upgraded. So each cluster froze whatever shipped on the day it was
created, and nobody ever chose a version. Every cluster now pins its image
explicitly, and the chart defaults new ones to 18.6.

## Current state

| Cluster | Running | OS base | Latest in series | Behind |
|---------|---------|---------|------------------|--------|
| paperless | 15.2 (Feb 2023) | bullseye | 15.19 | ~17 patches |
| multimedia ×3 | 16.2 (tag 16.1) | bullseye | 16.15 | ~13 |
| atuin | 16.11 | bullseye | 16.15 | 4 |
| mealie | 17.2 | bullseye | 17.11 | 9 |
| grafana | 17.5 | bullseye | 17.11 | 6 |
| pocket-id | 17.5 | bullseye | 17.11 | 6 |
| photos | 17.5 (VectorChord) | bookworm | — | tied to VectorChord |
| ai-gateway | 18.1 | trixie | 18.6 | 5 |
| mended-drum | 18.1 | trixie | 18.6 | 5 |

**Nothing is end-of-life.** PG15 runs to Nov 2027, 16 to Nov 2028, 17 to Nov
2029, 18 to Nov 2030. The exposure is missed patches, not EOL — paperless is the
outlier at roughly three and a half years of them.

## Two traps that decide the order

**`pg_upgrade` mounts the old binaries into the new container.** A major upgrade
across mismatched OS bases fails on missing shared libraries; this already bit
the immich migration (`libssl.so.1.1: cannot open shared object file`) and was
only resolved by stepping through a matching base. So a major upgrade must keep
the same Debian base on both sides.

**Changing the Debian base changes glibc, and glibc changes collation order.**
Text indexes built under one collation are silently wrong under another. Moving
bullseye → trixie is not a free swap: it needs a `REINDEX` of text indexes
afterwards. This is why base changes are a separate phase rather than something
to fold into a patch bump.

## Plan

The chart owns the version. `cnpg-database` 0.5.0 locks
`ghcr.io/cloudnative-pg/postgresql:17.11-standard-bookworm`, and each cluster
drops its own `imageName` as it is moved onto that. A pin now means "this
cluster cannot follow", not "this is what it happened to get".

17 on bookworm because it matches the VectorChord image immich needs, so photos
is not a major-version outlier. `17.x-system-bookworm` does not exist; the
variants are `minimal` and `standard`.

**Collation is a non-issue here.** Every database in the fleet is `collate=C`,
which compares by byte order and does not depend on glibc, so moving between
Debian bases needs no `REINDEX`. Confirmed on mealie: `datcollversion` is null
and the only index collations are `default` (inheriting C) and `C`.

### Done

    mealie      17.2  -> 17.11-standard-bookworm   unpinned
    grafana     17.5  -> 17.11-standard-bookworm   unpinned
    pocket-id   17.5  -> 17.11-standard-bookworm   unpinned
    prowlarr    16.1  -> 16.15                     (patch, still pinned)

### Staying pinned

    ai-gateway   18.1   PostgreSQL has no downgrade path
    mended-drum  18.1   ditto
    photos       17.5   tensorchord VectorChord build, moves on its own schedule

### Remaining: two steps each

15 and 16 clusters cannot go straight to 17.11-bookworm. `pg_upgrade` mounts the
**old** binaries into the **new** container, so a major upgrade across Debian
bases fails on missing libraries -- this is what broke the immich migration with
`libssl.so.1.1`. Move the base first, then the major:

    prowlarr/radarr/sonarr  16.x -> 16.15-standard-bookworm -> unpin (17.11)
    atuin                   16.11 -> 16.15-standard-bookworm -> unpin (17.11)
    paperless               15.2 -> 15.19-standard-bookworm -> unpin (17.11)

Step one is same-major, so it is a restart, not a `pg_upgrade`. Step two is the
offline `pg_upgrade`: take a backup and confirm it reached the bucket first.

## Before each upgrade

- `primaryUpdateMethod: switchover` refuses an image change and a config change
  in the same step. Land them separately.
- These HelmReleases take values via `valuesFrom` a ConfigMap. Changing the
  ConfigMap does **not** trigger an upgrade -- helm-controller waits out its 30m
  interval. Annotate the HelmRelease itself with `reconcile.fluxcd.io/requestedAt`
  or the image change appears to do nothing while everything reports Ready.
- pocket-id exits rather than retrying when postgres-rw blips, so it will
  restart during its primary's restart. It recovers on its own.
- CNPG will not shrink storage, so a live resize must be mirrored into git or
  the next Helm upgrade fails on the webhook.
