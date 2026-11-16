# HomeAssistantBackupStale { .quad-howto }

## Meaning

A backup timestamp for lancre's Home Assistant (on `home`) is over 36 hours
old. The `job` label tells you which one:

| `job` | Timestamp | Written by |
| --- | --- | --- |
| `scrapeConfig/lancre/node-exporter` | `hass_backup_copy_last_success_timestamp_seconds` | `/usr/local/bin/hass-backup-copy` on `home`, from `/etc/cron.d/hass-backup-copy` at 06:30, after it copies `/srv/homeassistant/config/backups/*.tar` to the UNAS share `hasszmc` |
| `scrapeConfig/lancre/homeassistant` | `sensor.backup_last_successful_automatic_backup` | Home Assistant's automatic backup, between 05:00 and 06:00 |

The copy stamps every run that finishes, even one with nothing new to copy.
So a fresh copy timestamp does not prove a fresh backup. Only the two together do.

## Impact

Nothing at the site stops working. A restore of `home` would lose everything
since the newest backup on the UNAS. The UNAS keeps the newest 30 copies.
Old copies are never pruned by age, so the share still holds the last good
backups.

## Diagnosis

1. Check how old each timestamp is, in hours.

    ```bash
    curl -s -G https://prometheus.ankhmorpork.thaum.xyz/api/v1/query \
      --data-urlencode 'query=(time() - hass_backup_copy_last_success_timestamp_seconds) / 3600 or (time() - hass_sensor_timestamp_seconds{entity="sensor.backup_last_successful_automatic_backup"}) / 3600'
    ```

2. If only the Home Assistant timestamp is old, check whether HA's backup
   manager is stuck. The state should be `idle`. Then read the
   *Backup* entries in the HA log (Settings → System → Logs).

    ```bash
    curl -s -G https://prometheus.ankhmorpork.thaum.xyz/api/v1/query \
      --data-urlencode 'query=hass_entity_available{entity=~"sensor.backup_.*"}'
    ```

3. If the copy timestamp is old, read the copy's last runs on `home`. `ok: N
   backups on UNAS` ends a good run. Anything else is the error that stopped
   it.

    ```bash
    ssh ssh-home.krupa.net.pl 'sudo journalctl -t hass-backup-copy --since "-3 days" --no-pager'
    ```

4. If the log shows a mount or NFS error, check that the UNAS exports the share
   to `home`.

    ```bash
    ssh ssh-home.krupa.net.pl '/sbin/showmount -e 192.168.40.10 | grep hasszmc'
    ```

## Mitigation

| Cause | Fix |
| --- | --- |
| HA made no backup | Fix what the HA log reports, then start a backup from Settings → System → Backups. The next 06:30 copy picks it up. |
| The copy failed to mount `hasszmc` | Bring the UNAS or the export back, then run the copy by hand: `ssh ssh-home.krupa.net.pl 'sudo /usr/local/bin/hass-backup-copy'`. |
| The copy ran out of space on the share | Free space on `hasszmc`, or lower `KEEP` in the script, then run it by hand. |
| The cron entry or script is gone (for example after a move to HAOS) | Restore them from [thaum-xyz/lancre#11](https://github.com/thaum-xyz/lancre/issues/11), or retire this alert along with the copy. |
