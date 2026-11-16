# HomeAssistantEnergySensorUnavailable { .quad-howto }

## Meaning

An entity that feeds the energy dashboard of lancre's Home Assistant (on
`home`) has been `unavailable` for every scrape of the last 24 hours. The
`entity` label names it. The alert covers these sources:

| Source | Entities |
| --- | --- |
| Micro-inverters (integration *GNE PV monitoring*) | `sensor.gne_pv_monitoring_<serial>_sensor_dailyenergy` |
| Huawei inverter, daily yield | `sensor.inwerter_dzienna_produkcja` |
| Grid import, export | `sensor.powermeter_total_active_energy`, `sensor.powermeter_total_active_returned_energy` |

The list is a regex in the rule. When a source is added in Settings →
Dashboards → Energy, add it there too.

The GNE sensors are `unavailable` every night, for about 10 hours. Panels under
snow can keep them unavailable for days.

## Impact

The energy dashboard shows no data for that source while it lasts. Once the
gap passes 10 days, Home Assistant has purged the short-term statistics it
continues the running `sum` from. When the sensor returns, its `sum` restarts
near 0, and the dashboard shows the drop as a large negative value. That
happened to all ten GNE sensors between 2026-09-26 and 2026-11-14.

## Diagnosis

1. List the energy sources that are unavailable now.

    ```bash
    curl -s -G https://prometheus.ankhmorpork.thaum.xyz/api/v1/query \
      --data-urlencode 'query=hass_entity_available{job="scrapeConfig/lancre/homeassistant", entity=~"sensor\\.(gne_pv_monitoring_.+|inwerter_.+|powermeter_.+)"} == 0'
    ```

2. Open the integration in Settings → Devices & services. A red *Failed to set
   up* or *Retrying setup* tile, or an error under its entry in Settings →
   System → Logs, is the cause.

3. For the GNE sensors, check the GNE monitoring portal. If it shows no data
   either, the inverters or their gateway are offline, not Home Assistant.

4. If the gap is over 10 days, or the sensor is back after one, look for a
   drop in its `sum`. Any row means the statistics need repair.

    ```bash
    kubectl -n lancre exec -i "$(kubectl -n lancre get pod -o name \
      -l cnpg.io/cluster=postgres,cnpg.io/instanceRole=primary)" -c postgres -- \
      psql -d homeassistant -c "
      SELECT statistic_id, to_timestamp(start_ts) AS start, sum, prev_sum
      FROM (SELECT m.statistic_id, s.start_ts, s.sum,
                   lag(s.sum) OVER (PARTITION BY s.metadata_id ORDER BY s.start_ts) AS prev_sum
            FROM statistics s JOIN statistics_meta m ON m.id = s.metadata_id
            WHERE m.statistic_id ~ '^sensor\.(gne_pv_monitoring_|inwerter_|powermeter_)') t
      WHERE sum < prev_sum ORDER BY statistic_id, start_ts;"
    ```

## Mitigation

| Cause | Fix |
| --- | --- |
| The integration failed to set up | Fix what its log entry says, then reload the integration from its tile. |
| The device or its cloud portal is offline | Bring the device back. Nothing to do in Home Assistant. |
| Snow on the panels | Wait. If it lasts over 10 days, repair the statistics afterwards. |
| The `sum` dropped after the gap | Repair the statistics, below. |

To repair the statistics, do this for each row step 4 of Diagnosis returns.
It needs no restart.

1. Note the row's `statistic_id`, its `start` (the first hour after the gap)
   and its `prev_sum` (the last `sum` before the gap).

2. Shift every row from `start` on by `prev_sum`. In Developer tools →
   Statistics, find the statistic, choose *Adjust sum*, pick the hour `start`
   and enter `prev_sum` in kWh. That runs this websocket command:

    ```json
    {"type": "recorder/adjust_sum_statistics", "statistic_id": "<statistic_id>",
     "start_time": "<start, ISO 8601>", "adjustment": <prev_sum>,
     "adjustment_unit_of_measurement": "kWh"}
    ```

   Home Assistant shifts the later rows in both `statistics` and
   `statistics_short_term`.

3. Run step 4 of Diagnosis again. It returns no rows once every statistic is
   repaired.
