# HomeAssistantBackupStale { .quad-howto }

## Meaning

`sensor.backup_last_successful_automatic_backup` of lancre's Home Assistant
(Home Assistant OS on `home`) is over 36 hours old. HA's automatic backup runs
daily and writes to two locations: the SD card and the UNAS share `hasszmc`,
mounted in HA as NFS network storage.

| Sensor | Moves when |
| --- | --- |
| `sensor.backup_ostatnia_proba_automatycznej_kopii_zapasowej` | an automatic backup starts, whatever the outcome |
| `sensor.backup_last_successful_automatic_backup` | an automatic backup is uploaded to every location without an error |

A location HA cannot load at all, such as a network mount that was removed, is
skipped without an error. The success timestamp still moves.

## Impact

Nothing at the site stops working. A restore of `home` would lose everything
since the newest complete backup. `hasszmc` keeps the newest 30 copies,
so older good backups are still there.

## Diagnosis

1. Compare the last attempt with the last success, in hours. A recent attempt
   and an old success mean the backup ran but an upload failed.

    ```bash
    curl -s -G https://prometheus.ankhmorpork.thaum.xyz/api/v1/query \
      --data-urlencode 'query=(time() - hass_sensor_timestamp_seconds{job="scrapeConfig/lancre/homeassistant", entity=~"sensor.backup_(last_successful_automatic_backup|ostatnia_proba_automatycznej_kopii_zapasowej)"}) / 3600'
    ```

2. Open Settings → System → Repairs. An issue about the automatic backup names
   the location that failed. Settings → System → Backups lists each backup
   with the locations it reached.

3. If the attempt is old too, check Settings → System → Backups → automatic
   backup settings: the schedule must be daily with both locations selected.
   Then read the *Backup* entries in Settings → System → Logs.

4. If the UNAS location failed, check the mount in Settings → System → Storage
   → Network storage, and that the UNAS still exports `hasszmc` to
   `192.168.20.4`.

    ```bash
    showmount -e 192.168.40.10 | grep hasszmc
    ```

## Mitigation

| Cause | Fix |
| --- | --- |
| No automatic backup ran | Fix the schedule or the error in the log, then Settings → System → Backups → Back up now → Automatic backup. |
| The upload to the UNAS failed | Bring the UNAS or the export back, reconnect the mount in Settings → System → Storage → Network storage, then Back up now → Automatic backup. |
| The card is full | Lower the number of copies kept in the automatic backup settings, then Back up now → Automatic backup. |
