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

Silences are created in the Alertmanager UI at
[alertmanager.ankhmorpork.thaum.xyz](https://alertmanager.ankhmorpork.thaum.xyz)
— **Silences → New Silence**, or the *Silence* button on a firing alert, which
prefills its labels and is usually the fastest correct start.

1. **Work out the narrowest matcher set that covers the work.** Prefer the
   labels that describe *what you are touching* over the ones that describe
   severity:

    | Work | Matchers |
    | --- | --- |
    | one app | `namespace=<namespace>` |
    | one node | `node=<node>`, and `instance=<ip>:<port>` for node-exporter alerts |
    | one storage backend | `namespace=<namespace>`, `alertname=~"drbd.*\|linstor.*"` |

2. **Set an expiry you will actually outlast, not a generous one.** A silence
   that expires while you are still working is a nuisance; one that outlives the
   work by hours is how a real outage goes unnoticed. Extend it rather than
   starting long.

3. **Read the preview before confirming.** Alertmanager lists the alerts the
   silence would match. That list is the check that matters — see the trap
   below.

4. **Expire it when you finish.** Do not wait for the timer.

If you would rather script it, `amtool` does the same thing against the same
API and takes matchers in the syntax above:

```bash
amtool silence add namespace=<namespace> --duration=2h --comment="<what you are doing>"
```

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
    confirm it is absent from the preview in step 3.

## Overnight work

Between 20:00 and 09:00 local, criticals do not page — they are still filed as
GitHub issues and page at 09:00 if they are still firing. You do not need a
silence to avoid being woken at night. You do need one to avoid the issues.

## Where the boundaries are set

The route tree, the receivers and the `waking-hours` interval live in
[`configmap-template.yaml`](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/apps/datalake-alerts/alertmanager/configmap-template.yaml).
The reboot window that makes node reboots unattended is `rebootDays` and
`startTime`/`endTime` in
[kured's values](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/platform/cluster/system-kured/values.yaml);
what those reboots do to a running cluster is
[Node reboots](../explanation/node-reboots.md).
