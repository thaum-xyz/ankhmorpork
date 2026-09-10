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

## 3. Build a kubeconfig

From a checkout of this repository, on the house network:

```bash
./hack/mkkubeconfig.py
```

That writes `~/.kube/clusters/ankhmorpork-oidc` and ends by verifying it. The
issuer, client ID and API server address come from `metal/group_vars/k3s.yml`, so
they cannot drift from what the API server accepts, and `offline_access` in the
generated credentials earns a refresh token — the passkey is needed once per
session rather than once per command.

## 4. Check the CA fingerprint

The script prints the cluster CA's SHA-256 fingerprint. Confirm it with someone
who already has cluster access before using the kubeconfig from a network you do
not control.

By default the CA comes from the API server's own TLS handshake, which is
trust-on-first-use: it is the client's only defence against trusting an impostor
API server and sending it a bearer token. With access to a control-plane node,
`-n <node>` reads the CA over SSH instead, which is authoritative and needs no
confirmation.

Verification output names the identity the cluster now sees — `oidc:` plus the
user's email address, with the `oidc:`-prefixed group from step 1 alongside
`system:authenticated`.

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
