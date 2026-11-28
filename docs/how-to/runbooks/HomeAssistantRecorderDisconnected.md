# HomeAssistantRecorderDisconnected { .quad-howto }

## Meaning

Lancre's Home Assistant (on `home`) answers its scrape, but no database
session of user `homeassistant` exists in the CNPG cluster `postgres` in
namespace `lancre`. HA reaches that cluster through the Service `postgres-lb`
at `postgres-lb.lancre.ankhmorpork.thaum.xyz`. A running recorder always holds
a connection. When Postgres metrics are missing, that also counts as no
connection.

The recorder tries 10 connects at start and then shuts down until HA Core
restarts. It does not retry once the database is back.

## Impact

History, logbook and energy statistics are not written for as long as it
lasts, and that gap stays in the history. Heating, igor and the automations
keep working.

## Diagnosis

1. Check whether the cluster is healthy and has a primary.

    ```bash
    kubectl -n lancre get cluster postgres
    ```

2. Check the backends per user. `homeassistant` missing while
   `cnpg_metrics_exporter` is present means Postgres is up and HA is not
   connected.

    ```bash
    curl -s -G https://prometheus.ankhmorpork.thaum.xyz/api/v1/query \
      --data-urlencode 'query=sum by (pod, usename) (cnpg_backends_total{namespace="lancre"})'
    ```

3. Check that beelink02 still routes replies to lancre through the UDM.
   Without rule 5240, handshakes from `home` to the VIP time out; see
   [metal/netplan/README.md](https://github.com/thaum-xyz/ankhmorpork/blob/master/metal/netplan/README.md).

    ```bash
    ssh beelink02 'ip rule show | grep 5240'
    ```

4. Read the recorder's errors in the HA log (Settings → System → Logs, filter
   `recorder`). `Error during connection setup` followed by `Shutting down
   recorder` means it gave up at start.

## Mitigation

| Cause | Fix |
| --- | --- |
| The cluster has no primary or its pods are down | Fix the cluster first. HA cannot reconnect before it is back. |
| The VIP does not answer from `home` | Check the `postgres-lb` Service has its address and the route from lancre to 192.168.50.137. |
| Postgres is up and answers, but the recorder gave up | Restart Home Assistant Core from Settings → System → Restart. History resumes. The gap stays. |
| Postgres metrics are missing, so the alert cannot see the session | Fix the CNPG metrics scrape. The recorder may still be fine; step 4 tells you. |
