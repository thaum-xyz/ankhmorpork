# Silence alerts for maintenance { .quad-howto }

Maintenance that takes a node or a service down fires the same alerts as an
outage. Create an Alertmanager silence before you start, so the work does not
page you and does not file issues you will only close again.

Silences are for **attended** work — you are at the keyboard, you know when you
started and when you are done. Recurring unattended work is handled by a time
interval in the route tree instead and needs nothing from you.

A silence stops the *notification*, not the alert: it still fires and still
burns SLO error budget, which is what keeps the budget able to tell you that
maintenance has grown too disruptive.

## Steps

Point `amtool` at the cluster once by putting this in
`~/.config/amtool/config.yml`, and it needs no flags afterwards:

```yaml
alertmanager.url: https://alertmanager.ankhmorpork.thaum.xyz
```

The [Alertmanager UI](https://alertmanager.ankhmorpork.thaum.xyz) does the same
job — **Silences → New Silence**, or the *Silence* button on a firing alert,
which prefills its labels.

1. **Work out the narrowest matcher set that covers the work.** Prefer the
   labels that describe *what you are touching* over the ones that describe
   severity:

    | Work | Matchers |
    | --- | --- |
    | one app | `namespace=<namespace>` |
    | one node | `node=<node>`, and `instance=<ip>:<port>` for node-exporter alerts |
    | one storage backend | `namespace=<namespace>`, `alertname=~"drbd.*\|linstor.*"` |

2. **See what those matchers actually hit, before creating anything.** This is
   the check that matters — see the trap below.

    ```bash
    amtool alert query <matcher> [<matcher>...]
    ```

3. **Create it with an expiry you will outlast, not a generous one.** A silence
   that expires mid-work is a nuisance; one that outlives the work by hours is
   how a real outage goes unnoticed. Extend rather than starting long.

    ```bash
    amtool silence add <matcher> [<matcher>...] --duration=2h --comment="<what you are doing>"
    ```

4. **Expire it when you finish.** Do not wait for the timer.

    ```bash
    amtool silence expire <silence-id>
    ```

`amtool silence query` lists the active silences, which is the quickest way
to find an id — or to catch a silence someone left behind.

!!! danger "Never let a silence match `Watchdog`"

    `Watchdog` fires permanently and is delivered to
    [healthchecks.io](https://healthchecks.io) every two minutes. It is a
    dead-man's switch: silence it and the missing heartbeat raises an alert
    *outside* this cluster, which is the one thing you cannot silence from
    inside it.

    It carries `severity=none` and is matched by `alertname`, so no
    severity-based silence can reach it. What reaches it is a silence whose
    matchers are too loose — a bare cluster-wide match, or an `alertname=~".*"`.
    Give every silence at least one matcher `Watchdog` cannot satisfy, and
    confirm it is absent from the step 2 output.

## Overnight work

Between 20:00 and 09:00 local, criticals do not page — they are still filed as
GitHub issues and page at 09:00 if they are still firing. You do not need a
silence to avoid being woken at night. You do need one to avoid the issues.

## Changing the routing itself

The rendered configuration is checked by `make validate-alertmanager`, which is
also a CI job. Run it after any edit to the route tree: kustomize and
kubeconform only see the config as an opaque string inside a ConfigMap, so an
undefined receiver, a missing time interval or an unloadable timezone otherwise
reaches the cluster and surfaces only as `AlertmanagerFailedReload`.

It renders the template with `esoctl` and checks the result with
`amtool check-config`, so esoctl, amtool and yq all have to be installed — the
target says how if they are not.

## Where the boundaries are set

The route tree, the receivers and the `waking-hours` interval live in
[`configmap-template.yaml`](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/apps/datalake-alerts/alertmanager/configmap-template.yaml).
The reboot window that makes node reboots unattended is `rebootDays` and
`startTime`/`endTime` in
[kured's values](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/platform/cluster/system-kured/values.yaml);
what those reboots do to a running cluster is
[Node reboots](../explanation/node-reboots.md).
