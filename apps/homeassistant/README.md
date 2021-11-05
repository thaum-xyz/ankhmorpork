# HomeAssistant

## State management

Following files are managed via jsonnet and are read only to home assistant installation:
- `configuration.yaml`
- `scripts.yaml`
- `customize.yaml`

Following, important, configuration files are stored on PVC:
- automations.yaml
- secrets.yaml

## Backups

Everything stored on PVC is backed up the same way as other NFS-backed volumes.
