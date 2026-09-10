# Log in with kubectl { .quad-howto }

The API server trusts pocket-id as an OIDC issuer, so `kubectl` can authenticate
with a passkey instead of a client certificate. Permissions come from **pocket-id
group membership**: each group a user belongs to arrives in the token and becomes
a Kubernetes group named `oidc:<group>`, which is what RBAC binds to.

Two independent things must both be true, and they fail in different ways:

| Requirement | Where it lives | Failure if missing |
| --- | --- | --- |
| The user may use the kubectl OIDC client | `Allowed User Groups` on that client in pocket-id | `access_denied` during login, before Kubernetes sees anything |
| The user's group is bound to a role | `k8s/platform/security/oidc-rbac/` | login succeeds, then every command is `Forbidden` |

## 1. Join the groups

In pocket-id, add the user to the group for the access level they need, and make
sure that same group is selected under `Allowed User Groups` on the kubectl
client. A newly created client allows **no** groups at all.

| Pocket-id group | Kubernetes group | Gets |
| --- | --- | --- |
| `k8s-admins` | `oidc:k8s-admins` | `cluster-admin` |
| `k8s-viewers` | `oidc:k8s-viewers` | `view` cluster-wide |

## 2. Install the credential plugin

```bash
kubectl krew install oidc-login
```

## 3. Fetch the kubeconfig

On the house network or over tailscale:

```bash
curl -o ~/.kube/clusters/ankhmorpork-oidc \
  https://kubeconfig.ankhmorpork.thaum.xyz/kubeconfig
```

The file carries the API server address, the cluster CA and the OIDC client
settings, and `offline_access` in it earns a refresh token — the passkey is
needed once per session rather than once per command.

It is built inside the cluster from what the API server is actually running on:
the issuer and client ID come from its `authentication-config.yaml`, the address
from the node's `tls-san`, and the CA from the `kube-root-ca.crt` ConfigMap the
control plane maintains. Nothing is copied or transcribed, so the kubeconfig
cannot disagree with what the API server accepts.

Nothing in it is secret. The address and client ID are public by design, and the
API server hands the CA to every anonymous TLS client — which is why the endpoint
sits behind no login. It is served over HTTPS with a certificate the machine's
own trust store validates, so the CA arrives from a source already trusted rather
than from the connection it is meant to protect.

## 4. Check it works

```bash
KUBECONFIG=~/.kube/clusters/ankhmorpork-oidc kubectl auth whoami
```

A browser opens for the passkey. The output names the identity the cluster now
sees — `oidc:` plus the user's email address, with the `oidc:`-prefixed group
from step 1 alongside `system:authenticated`.

!!! warning "Every pocket-id group becomes a Kubernetes group"

    The `groups` claim carries *all* of a user's pocket-id groups, including the
    ones that exist for unrelated applications. So a group named for an app is
    also a live cluster identity: bind `oidc:monitoring` and everyone who was
    added to that group for Grafana silently gains it in Kubernetes too. Give
    groups intended for cluster access a `k8s-` prefix and never bind a bare
    application group name.

## 5. Grant a narrower level

Add a binding under `k8s/platform/security/oidc-rbac/`, subject kind `Group`,
name `oidc:<group>`. A `RoleBinding` that points at a `ClusterRole` applies that
role's rules inside one namespace only, which is how to hand over an app without
handing over the cluster:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: oidc-mealie-admins
  namespace: mealie
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: Group
    name: oidc:k8s-mealie
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: admin
```

Reach for the built-in roles before writing rules. `view` is read-only and
excludes Secrets, though it does read every ConfigMap in scope; `edit` can write
most objects *and* read Secrets there; `admin` adds RBAC within the namespace.

## 6. When it fails

| Symptom | Cause |
| --- | --- |
| `access_denied … not allowed to access this service` | the group is not in the client's `Allowed User Groups` |
| authenticates, then `Forbidden` | no binding matches any `oidc:` group the user holds |
| `oidc: email not verified` | the account's email is not marked verified in pocket-id |
| a stale identity after a group change | cached token; clear `~/.kube/cache/oidc-login` |

The API server reads its authenticator from a file written by the `k3s-master`
ansible role and **hot-reloads it**, so changing claim or group mapping costs no
restart. Adding or removing the flag that points at it does restart the control
plane.
