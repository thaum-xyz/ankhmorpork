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

Slowly, one cluster at a time, verifying before moving on.

**Phase 1 — patch upgrades, same major and same OS base.** No `pg_upgrade`, no
collation change; CNPG rolls replicas then switches over. Lowest risk.

    paperless   15.2  -> 15.19-system-bullseye
    multimedia  16.1  -> 16.15-system-bullseye   (prowlarr, then radarr, sonarr)
    atuin       16.11 -> 16.15-system-bullseye
    mealie      17.2  -> 17.11-system-bullseye
    grafana     17.5  -> 17.11-system-bullseye
    pocket-id   17.5  -> 17.11-system-bullseye
    ai-gateway  18.1  -> 18.6-system-trixie
    mended-drum 18.1  -> 18.6-system-trixie

Start with multimedia: three near-identical clusters whose downtime costs
nothing, so they are the cheapest place to find out that something is wrong.

**Phase 2 — major upgrades to 18, holding the OS base constant.** Offline
`pg_upgrade`, so real downtime. Take a backup first and verify it lands.

    multimedia  16.15 -> 18.6-system-bullseye
    atuin       16.15 -> 18.6-system-bullseye
    mealie/grafana/pocket-id 17.11 -> 18.6-system-bullseye
    paperless   15.19 -> 18.6-system-bullseye

**Phase 3 — move onto trixie, then `REINDEX`.** Do this last and per cluster,
because it is the collation-sensitive step.

`photos` sits outside all of this: it runs `tensorchord/cloudnative-vectorchord`
for the immich embeddings and can only move when that image publishes a matching
build. Do not point it at a stock CNPG image.

## Before each upgrade

- `primaryUpdateMethod: switchover` refuses an image change and a config change
  in the same step. Land them separately.
- Take a backup and confirm it reached the bucket, rather than assuming.
- CNPG will not shrink storage, so a live resize must be mirrored into git or
  the next Helm upgrade fails on the webhook.
