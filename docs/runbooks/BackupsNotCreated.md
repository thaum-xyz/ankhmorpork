# BackupsNotCreated

## Meaning

<!-- What this alert is about? -->

[Restic Robot](https://github.com/Southclaws/restic-robot) couldn't create data backups.

## Impact

<!-- What this alert affects? -->

Data consistency can be at risk.

## Diagnosis

<!-- How to check symptoms of the alert firing? -->

Check logs of restic-robot application.

## Mitigation

<!-- How to solve the issue? -->

Application logs should point to what needs to be done. In most cases it is because restic respoitory is locked
and needs to be unlocked.

### How to unlock restic repository

0. Have `restic` binary installed
1. Import environment variables from `restic-repository` secret associated with the failing job/deployment.
```bash
export secret="restic-repository"
export $(kubectl get secret "$secret" -ojson | jq -r ".data | to_entries|map(\"\(.key)=\(.value|tostring|@base64d)\")|.[]")
```
2. Execute `restic unlock`
3. Unset environment variables.
```
export secret="restic-repository"
unset $(kubectl get secret "${secret}" -ojson | jq -r ".data | to_entries|map(\"\(.key)\")|.[]")
```
