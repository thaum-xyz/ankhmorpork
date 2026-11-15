# WANDown { .quad-howto }

## Meaning

The UniFi gateway named in the `name` label reports its primary WAN
(`wan_networkgroup="WAN"`) offline, read through unpoller. The alert keeps
firing for 30 minutes after the WAN returns, to cover the alerts that clear
behind it.

## Impact

The site is cut off in both directions while it lasts. Everything on the LAN
keeps working.

| Direction | What stops |
| --- | --- |
| Inbound | every public host behind the Cloudflare tunnel, and zmc.krupa.net.pl, which shares the uplink |
| Outbound | Flux fetches from GitHub, image pulls, and every Alertmanager receiver: alerts queue and arrive after the WAN is back, this one included |

While it fires, Alertmanager holds back `SiteExternallyDown`,
`FluxCDReconciliationFailure` and `sonarrUnhealthy`: all three follow from the
outage. A real fault of
either kind is still firing when the hold ends, and is sent then.

## Diagnosis

1. Confirm the gateway still reports the WAN offline. `0` means offline.

    ```bash
    curl -s -G https://prometheus.ankhmorpork.thaum.xyz/api/v1/query \
      --data-urlencode 'query=unpoller_device_wan_status{wan_networkgroup="WAN"}'
    ```

2. Check whether the gateway's WAN port lost its link. A reset of this
   counter at the start of the outage means the link dropped, rather than the
   ISP's network.

    ```bash
    curl -s -G https://prometheus.ankhmorpork.thaum.xyz/api/v1/query \
      --data-urlencode 'query=unpoller_device_uplink_uptime_seconds{name="Ankhmorpork Unseen"}'
    ```

3. Check that the Cloudflare tunnel lost its edge connections at the same
   time. Fewer than 4 means the edge is unreachable.

    ```bash
    curl -s -G https://prometheus.ankhmorpork.thaum.xyz/api/v1/query \
      --data-urlencode 'query=cloudflared_tunnel_ha_connections'
    ```

## Mitigation

| Cause | Fix |
| --- | --- |
| The WAN port lost its link | Check the cable and the ISP router in front of the gateway; power-cycle the ISP router. |
| The link is up and the ISP does not route | Wait, or report it to the ISP. Nothing in the cluster fixes it. |
| The WAN is back and issues from the outage remain | Flux catches up on its own intervals; close the issues it filed once they resolve. |
