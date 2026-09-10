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

Groups are named `k8s:<scope>:<tier>`, the colon-separated shape Kubernetes uses
for its own `system:` groups.

| Pocket-id group | Kubernetes group | Gets |
| --- | --- | --- |
| `k8s:cluster:admin` | `oidc:k8s:cluster:admin` | `cluster-admin` |
| `k8s:cluster:view` | `oidc:k8s:cluster:view` | `view` cluster-wide |
| `k8s:group:<name>` | `oidc:k8s:group:<name>` | whatever each namespace grants it |

A `k8s:group:` group has no tier of its own. Each namespace decides what that
group gets there, so one group covers however many namespaces name it, at a
different level in each if you like — which means groups scale with people
rather than with namespaces. Nothing creates these groups for you: the
Kubernetes side is generated, the pocket-id side is not.

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
    groups intended for cluster access the `k8s:` prefix above, and never bind a
    bare application group name.

## 5. Hand someone a single namespace

Label the Namespace once per group that should reach it, naming the group in the
key and its level in the value. Nothing else on the Kubernetes side is written
by hand:

```yaml
metadata:
  labels:
    group.rbac.thaum.xyz/media: edit
    group.rbac.thaum.xyz/guests: view
```

Each label generates a `RoleBinding` giving `oidc:k8s:group:<group>` that
ClusterRole in that namespace, and keeps it in sync — so removing a label
removes that group's access. Label keys are unique, so any number of groups can
share a namespace at different levels. `edit` and `view` are the only accepted
values; anything else is rejected at admission. A `RoleBinding` pointing at a
`ClusterRole` applies that role's rules inside one namespace only, which is how
an app gets handed over without handing over the cluster.

The group name comes from the label key, and the `k8s:group:` prefix is prepended
rather than written out. Pocket-id groups are shared with every other
application — `oidc:mealie` is already the Mealie app's own SSO group — so that
prefix is what keeps a label from pointing cluster access at one of them. A
mistyped key names a group that does not exist, which grants nothing.

`view` is read-only and excludes Secrets, though it reads every ConfigMap in
scope. `edit` writes most objects *and* reads Secrets there. Neither reaches the
app's SLO, its Postgres cluster or its generated alert rules — those API groups
are absent from both roles.

!!! warning "In a Flux-managed cluster this is not "manage the app""

    Flux applies with server-side apply and force, so an edit to anything it
    owns is reverted on the next reconcile, and the `Kustomization` that governs
    the app lives in `flux-system` rather than the app's namespace. What the
    grant really provides is the operational surface: logs, `exec`,
    `port-forward`, deleting a pod to restart it, scaling for a minute. Durable
    change still goes through a pull request.

## 6. When it fails

| Symptom | Cause |
| --- | --- |
| `access_denied … not allowed to access this service` | the group is not in the client's `Allowed User Groups` |
| authenticates, then `Forbidden` | no binding matches any `oidc:` group the user holds |
| `oidc: email not verified` | the account's email is not marked verified in pocket-id |
| a stale identity after a group change | cached token; clear `~/.kube/cache/oidc-login` |
| a namespace label is rejected | a `group.rbac.thaum.xyz/<group>` label accepts only `edit` or `view` |
| the label is set but no RoleBinding appears | kyverno's background controller reconciles it; check its logs and the `UpdateRequest` objects |

The API server reads its authenticator from a file written by the `k3s-master`
ansible role and **hot-reloads it**, so changing claim or group mapping costs no
restart. Adding or removing the flag that points at it does restart the control
plane.
