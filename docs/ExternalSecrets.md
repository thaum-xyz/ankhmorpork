# ExternalSecrets

## Doppler secret

All secrets are in [doppler](https://www.doppler.com/). To allow external-secrets operator access to those secrets, you need to create a token in doppler and add it to the cluster as a secret. This secret needs to be named `doppler-token` and placed in `external-secrets` namespace as this is the name referenced in `ClusterSecretStore` resource already preinstalled in the cluster. Below is a snippet of the `Secret` resource:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: doppler-token
  namespace: external-secrets
type: Opaque
data:
  token: <base64 encoded token>
```

Without this secret, external-secrets operator will not be able to access secrets in doppler and `ClusterSecretStore` will be in `InvalidProvidercConfig` state. However this secret can be applied at any time and operator will start working.

## Doppler token (re)creation

Doppler service token is used to access secrets in doppler. To create a new token, follow the steps below:

1. Login to doppler
2. Go to `Projects` -> `Ankhmorpork` -> `Access`
3. Under `Service Tokens` click `Generate`
4. Generate read-only token
