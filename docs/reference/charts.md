# Charts and images { .quad-reference }

Two repositories hold code this cluster depends on. They were split out of
`ankhmorpork` so that chart testing, image builds and releases have their own CI
— not because they have an audience of their own.

This page is a map. It says what exists, who consumes it, and where the
authoritative reference lives. It deliberately does **not** copy values tables
here: a chart's values are invalidated by a diff in the chart repository, so a
copy in this repository would go stale without anything in a pull request ever
hinting that it had.

!!! info "Why the reference is elsewhere"

    Renovate bumps chart versions in this repository, so a chart change does
    eventually appear here — as a version string. `0.10.1` → `0.11.0` in a
    HelmRelease says nothing about which values moved, so it would never prompt
    anyone to correct a values table living here. That table is only reliably
    correct next to the chart, which is why it is generated there instead.

## Charts

Published to `oci://ghcr.io/thaum-xyz/helm-charts`, source in
[thaum-xyz/helm-charts][hc]. Values reference is generated from each chart's
`values.yaml` and verified in that repository's CI.

[hc]: https://github.com/thaum-xyz/helm-charts

| Chart | Purpose | Used by | Values |
| --- | --- | --- | --- |
| `cnpg-database` | CloudNativePG cluster with barman-cloud object store, scheduled backups, Doppler-backed credentials and backup alerting | all eleven Postgres databases | [reference][v-cnpg] |
| `lvm-diskprep` | Prepares LVM node disks for CSI stacks via privileged DaemonSets and textfile metrics | `topolvm-system` | [reference][v-lvm] |

[v-cnpg]: https://github.com/thaum-xyz/helm-charts/tree/main/charts/cnpg-database
[v-lvm]: https://github.com/thaum-xyz/helm-charts/tree/main/charts/lvm-diskprep

## Images

Published to `ghcr.io/thaum-xyz/containers/<name>`, source in
[thaum-xyz/containers][co]. Tagged `YYYY.WW.PATCH`; there is no `latest`.

[co]: https://github.com/thaum-xyz/containers

| Image | Purpose | Used by |
| --- | --- | --- |
| `lvm-tools` | Debian with `lvm2` and `util-linux` for privileged node disk preparation | the `lvm-diskprep` chart |

Nothing in `k8s/` references that image directly. It reaches the cluster only
when the chart's image tag is bumped and the chart is then released — two hops,
which is worth remembering when a fix appears not to have landed.

## Where the S3 gateways come from

All three S3 gateways — `cnpg-system`, `longhorn-system` and `datalake-logs` —
run [upstream's chart][up] at v0.3.5 from `oci://ghcr.io/versity/versitygw/charts`,
not a thaum-xyz chart. Their values follow upstream's shape: `gateway.backend`,
`persistence`, `auth.existingSecret`.

A thaum-xyz `versitygw` chart did exist, shaped differently (`storage.data`,
`bucketName`) and stuck at 0.1.0. It was confirmed to have no consumer — here,
in any sibling repository, or in the live cluster — and was deleted from
`helm-charts` on 2026-09-06. The published
`oci://ghcr.io/thaum-xyz/helm-charts/versitygw:0.1.0` was left in place rather
than pulled, so nothing that already referenced it can break. Anything reaching
for a gateway chart should use upstream's.

[up]: https://github.com/versity/versitygw/tree/main/chart

## The backup loop

`cnpg-database` writes backups to the versitygw gateway in `cnpg-system` —
`http://versitygw.cnpg-system.svc.cluster.local:7070`, from the upstream chart —
which stores objects on a `unifi-nas` volume. Restoring any database depends on
that gateway and that volume as well as on CloudNativePG. See
[Postgres fleet upgrade plan](../postgres/fleet-upgrade-plan.md) for the state
of the fleet itself.
