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

## 3. Write a kubeconfig

The issuer is `https://login.krupa.net.pl`. For the client ID use
`k3s_oidc_client_id` from `metal/group_vars/k3s.yml`, which is the value the API
server is configured to accept as the audience.

```yaml
apiVersion: v1
kind: Config
current-context: ankhmorpork
clusters:
  - name: ankhmorpork
    cluster:
      server: https://100.127.115.15:6443
      certificate-authority-data: <same CA as the certificate kubeconfig>
users:
  - name: pocket-id
    user:
      exec:
        apiVersion: client.authentication.k8s.io/v1
        command: kubectl
        args:
          - oidc-login
          - get-token
          - --oidc-issuer-url=https://login.krupa.net.pl
          - --oidc-client-id=<client-id>
          - --oidc-extra-scope=email
          - --oidc-extra-scope=groups
          - --oidc-extra-scope=offline_access
          - --oidc-pkce-method=S256
        interactiveMode: IfAvailable
contexts:
  - name: ankhmorpork
    context:
      cluster: ankhmorpork
      user: pocket-id
```

`offline_access` is what earns a refresh token, so the passkey is needed once per
session rather than once per command. `interactiveMode` is mandatory under the
`v1` exec API.

## 4. Verify

```bash
kubectl auth whoami
```

The username is `oidc:` plus the user's email address, and the groups list should
contain the `oidc:`-prefixed group from step 1 alongside `system:authenticated`.

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
