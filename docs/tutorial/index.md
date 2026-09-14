# Deploy your first app { .quad-tutorial }

By the end of this you will have deployed an application to the cluster, watched
Flux pick it up, seen it answer over HTTPS on its own hostname, and removed it
again — about twenty minutes, most of it waiting.

The app is `whoami`: a few megabytes, no storage, no configuration. It echoes back
the request it received, which is exactly what you want the first time, because the
page it returns is proof that every layer worked.

You are not learning `whoami`. You are learning how anything gets into this
cluster.

!!! note "This deploys to the real cluster"

    There is no staging environment. You will create a real namespace, a real DNS
    record and a real certificate — then delete all of it in the last step. This
    is safe: nothing else depends on what you are about to make.

## Before you start

You need:

- A clone of this repository, and permission to merge a pull request.
- `kubectl` and `flux` on your PATH, with `KUBECONFIG=~/.kube/clusters/ankhmorpork`.
- `kustomize` and `kubeconform`, used by `make validate`.

Check the connection:

```bash
export KUBECONFIG=~/.kube/clusters/ankhmorpork
kubectl get nodes
```

You should see the cluster's nodes, all `Ready`. If that fails, stop here and fix
it — nothing below will work.

Start from a branch:

```bash
git switch master && git pull
git switch -c tutorial-whoami
```

## Step 1 — Write the manifests

An app is split by who owns each half. `k8s/apps/<app>/` holds what the app *is*,
and is reconciled by a Kustomization confined to the app's own namespace.
`k8s/namespaces/<app>/` holds what has to exist before that can happen — the
Namespace, the source, the Kustomization itself — and is applied with
cluster-admin. Step 2 builds the second; this one builds the first.

```bash
mkdir -p k8s/apps/whoami
```

One Kubernetes object per file, named after the object type. Create these three.

Note what is *not* here: a `Namespace`. It is cluster-scoped, and the identity
this directory is reconciled by is confined to one namespace — it could not
apply one. That is step 2's job.

`k8s/apps/whoami/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: whoami
spec:
  replicas: 1
  selector:
    matchLabels:
      app: whoami
  template:
    metadata:
      labels:
        app: whoami
    spec:
      containers:
        - name: whoami
          image: traefik/whoami:v1.12.0
          ports:
            - name: http
              containerPort: 80
          resources:
            requests:
              cpu: 10m
              memory: 32Mi
```

`k8s/apps/whoami/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: whoami
spec:
  selector:
    app: whoami
  ports:
    - name: http
      port: 80
      targetPort: http
```

`k8s/apps/whoami/ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: whoami
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: private
  rules:
    - host: whoami.ankhmorpork.thaum.xyz
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: whoami
                port:
                  name: http
  tls:
    - hosts:
        - whoami.ankhmorpork.thaum.xyz
      secretName: whoami-tls
```

Finally, the kustomization that ties them together —
`k8s/apps/whoami/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: whoami
resources:
  - deployment.yaml
  - service.yaml
  - ingress.yaml
```

That `namespace:` line is doing real work: it is what puts every object above into
the `whoami` namespace without any of them saying so individually.

## Step 2 — Give it a namespace, a source and an identity

Flux does not scan for new directories, and a Kustomization can create neither
the namespace it runs in nor the source it reads. Those are prerequisites, so
they live together in `k8s/namespaces/whoami/`, which the cluster-admin
`namespaces` Kustomization applies.

```bash
mkdir -p k8s/namespaces/whoami
```

`k8s/namespaces/whoami/namespace.yaml` — the label is what makes Kyverno generate
the `flux-reconciler` ServiceAccount and its RoleBinding here, and the
`GitRepository` the Kustomization below reads. A RoleBinding, so `cluster-admin`
means namespace-admin in `whoami` and nothing anywhere else:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: whoami
  annotations:
    kustomize.toolkit.fluxcd.io/prune: disabled
  labels:
    flux.rbac.thaum.xyz/role: cluster-admin
    pod-security.kubernetes.io/enforce: baseline
```

`k8s/namespaces/whoami/sync.yaml` — the Kustomization, in the app's namespace:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: whoami
  namespace: whoami
spec:
  interval: 15m0s
  path: ./k8s/apps/whoami
  prune: true
  sourceRef:
    kind: GitRepository
    name: ankhmorpork
```

`namespace: whoami` on that last object is the important line. It is what makes
this reconcile as `whoami`'s own ServiceAccount rather than a cluster-admin one,
so the app can only ever touch its own namespace. `sourceRef` names a
`GitRepository` you did not write: `--no-cross-namespace-refs` means a
Kustomization may only name a source in its own namespace, so Kyverno generates
one there from the label above.

`prune: true` means deleting the directory later deletes the objects too, which is
what makes the cleanup step at the end work. The Namespace itself opts out of
pruning, so that no restructure can ever delete it with everything inside.

## Step 3 — Validate before pushing

```bash
git add k8s/apps/whoami k8s/namespaces/whoami
make validate
```

The `git add` is not optional. `make validate` reads **git-tracked** files, so an
unstaged new directory validates as though it does not exist — it will report
success while checking nothing.

The last line should end `render and validate cleanly`, with a target count one
higher than the run before you added the app:

```text
All 125 targets render and validate cleanly.
```

The absolute number grows as the cluster does, so compare it with your own
previous run rather than with the number printed here.

## Step 4 — Merge it

```bash
git commit -m "whoami: tutorial app"
git push -u origin tutorial-whoami
gh pr create --fill
```

Wait for the checks, then merge. Flux only reads `master`, so nothing happens
until you do.

## Step 5 — Make Flux notice

Flux polls, so it will find this within a few minutes on its own. To watch it
happen now, reconcile in this order:

```bash
flux -n platform-cluster reconcile source git ankhmorpork
flux -n platform-cluster reconcile kustomization namespaces
flux -n whoami reconcile kustomization whoami
```

The order matters. The first command pulls the new commit; without it the other
two can act on a revision from before your merge and report success having done
nothing. The second makes `namespaces` create the namespace, the source and the
Kustomization — none of your `whoami` objects exist in the cluster until then.

Note the `-n platform-cluster` on the source. Several `GitRepository` objects are
named `ankhmorpork`, one per namespace that reconciles; the umbrellas read the one
in `platform-cluster`. Refreshing a different one leaves them on a stale revision
and still reports success.

Now watch the pod arrive:

```bash
kubectl -n whoami get pods -w
```

Wait for `Running`, then press ++ctrl+c++.

## Step 6 — See it work

The certificate takes a minute or two. Watch for it:

```bash
kubectl -n whoami get certificate -w
```

Wait until `READY` is `True`, then press ++ctrl+c++ and make a request:

```bash
curl https://whoami.ankhmorpork.thaum.xyz/
```

You should get something like:

```text
Hostname: whoami-6d7f9c8b4-xk2wq
IP: 127.0.0.1
IP: 10.42.3.17
RemoteAddr: 10.42.0.9:41234
GET / HTTP/1.1
Host: whoami.ankhmorpork.thaum.xyz
X-Forwarded-For: 192.168.50.42
X-Forwarded-Proto: https
```

Read that output for a moment, because it is the whole point:

- **`Hostname`** is your pod. Kubernetes scheduled it.
- **`Host`** is your name. `external-dns` published it to the house resolver.
- **`X-Forwarded-Proto: https`** means Traefik terminated a certificate that
  `cert-manager` obtained for a hostname that did not exist ten minutes ago.

Nothing in the manifests you wrote mentioned DNS or certificates. Both happened
because the Ingress existed.

It also works in a browser at
<https://whoami.ankhmorpork.thaum.xyz>, from anywhere on the house network —
`private` means exactly that, and nothing you made is reachable from outside.

## Step 7 — Remove it

Delete both pieces and merge again:

```bash
git switch -c tutorial-whoami-cleanup
git rm -r k8s/apps/whoami k8s/namespaces/whoami
git commit -m "whoami: remove tutorial app"
git push -u origin tutorial-whoami-cleanup
gh pr create --fill
```

After merging:

```bash
flux -n platform-cluster reconcile source git ankhmorpork
flux -n platform-cluster reconcile kustomization namespaces
kubectl get namespace whoami
```

That last command should report `NotFound` — the pod, the certificate and the DNS
record went with the namespace, because `prune: true` means Flux owns what it
created.

If the namespace lingers, that is expected rather than a failure: `namespaces` is
`prune: false`, precisely so that deleting a directory can never cascade into
deleting a namespace and everything in it. Removing one is deliberately two acts:

```bash
kubectl delete namespace whoami
```

## What you just learned

- An app is a **directory plus a Flux Kustomization**. There is no registry, no
  install command, and nothing to click.
- **Git is the interface.** Everything reached the cluster by being merged. You
  never ran `kubectl apply`.
- **`make validate` reads staged files**, so `git add` comes first.
- **Reconcile source before Kustomization**, or you will get a confident success
  message about a revision that predates your change.
- **An Ingress buys more than routing** — DNS and a certificate arrived with it.

## Where to go next

This was a lesson, so it made every choice for you. Real work needs those choices
back:

- **[Expose an app on an ingress](../how-to/expose-an-app.md)** — you wrote one
  in step 1 and every choice in it was made for you. This explains them, and why
  a host reachable from outside the house needs two.
- **[Choose a storage class](../how-to/choose-a-storage-class.md)** — the first
  real decision most apps hit. `whoami` had no storage; almost nothing else is so
  lucky, and the choice is hard to reverse.
- **[How-to](../how-to/index.md)** — the same steps for an app that needs
  a database or a public hostname.
- **[Reference](../reference/index.md)** — the storage classes, ingress classes
  and admission policies you skipped past. The Ingress above satisfies
  `validate-ingress-contract`, which *denies* anything missing TLS or using an
  unapproved issuer; the resource requests satisfy `require-resource-requests`,
  which only warns. Both were chosen for you here.
- **[How Flux is layered](../explanation/flux-layering.md)** — why step 5's
  reconcile order is what it is, and why getting it wrong reports success.
- **[Explanation](../explanation/index.md)** — why the cluster is arranged this
  way.
