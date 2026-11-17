# HomeAssistantEnergySensorStale { .quad-howto }

## Meaning

None of the ten GNE micro-inverter sensors of lancre's Home Assistant (on
`home`), `sensor.gne_pv_monitoring_<serial>_sensor_dailyenergy`, has changed
for 2 hours, while the Huawei inverter's `sensor.inwerter_dzienna_produkcja`
grew by more than 0.2 kWh. Both arrays see the same sky, so the sensors are
frozen, not idle.

When a call to the GNE API (`newapi.gnetek.com`) fails, the integration keeps
serving its last good answer. The sensors stay available, so
[HomeAssistantEnergySensorUnavailable](HomeAssistantEnergySensorUnavailable.md)
stays quiet. On 2026-11-17 DNS on `home` failed from 03:25 to 16:20 CET and
the sensors held one value for about 21 hours.

## Impact

The energy dashboard under-reports micro-inverter production for as long as
it lasts. The daily counter catches up once the API answers again the same
day. A freeze that runs past midnight loses the rest of that day's
production.

## Diagnosis

1. Check that `home` resolves the GNE API.

    ```bash
    ssh ssh-home.krupa.net.pl 'getent hosts newapi.gnetek.com'
    ```

2. Read the GNE entries in the HA log (Settings → System → Logs, filter
   `gne_pv_monitoring`). Timeouts or connection errors on every update mean
   the API is unreachable from `home`.

3. Check the GNE monitoring portal. If it shows no fresh data either, the
   inverters or their gateway are offline.

## Mitigation

| Cause | Fix |
| --- | --- |
| `home` cannot resolve or reach the API | Fix DNS or the uplink on `home`. The sensors update on the next poll. |
| The API answers but the sensors stay frozen | Reload the integration from Settings → Devices & services → GNE PV monitoring. |
| The inverters or gateway are offline | Bring them back. Nothing to do in Home Assistant. |
