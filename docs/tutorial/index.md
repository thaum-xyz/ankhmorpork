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

An app is a directory of manifests plus a Flux Kustomization pointing at it.
Nothing registers it anywhere else; the directory *is* the app.

```bash
mkdir -p k8s/apps/whoami
```

One Kubernetes object per file, named after the object type. Create these four.

`k8s/apps/whoami/namespace.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: whoami
```

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
  - namespace.yaml
  - deployment.yaml
  - service.yaml
  - ingress.yaml
```

That `namespace:` line is doing real work: it is what puts every object above into
the `whoami` namespace without any of them saying so individually.

## Step 2 — Tell Flux about it

Flux does not scan for new directories. Point it at the one you just made, in
`k8s/flux/apps/whoami.yaml`:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: whoami
  namespace: flux-system
spec:
  interval: 15m0s
  path: ./k8s/apps/whoami
  prune: true
  sourceRef:
    kind: GitRepository
    name: ankhmorpork
```

`prune: true` means deleting the directory later deletes the objects too, which is
what makes the cleanup step at the end work.

## Step 3 — Validate before pushing

```bash
git add k8s/apps/whoami k8s/flux/apps/whoami.yaml
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
flux reconcile source git ankhmorpork
flux -n flux-system reconcile kustomization apps
flux -n flux-system reconcile kustomization whoami
```

The order matters. The first command pulls the new commit; without it the other
two can act on a revision from before your merge and report success having done
nothing. The second makes the `apps` group notice that a new Kustomization exists
at all — your `whoami` Kustomization does not exist in the cluster until then.

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
git rm -r k8s/apps/whoami k8s/flux/apps/whoami.yaml
git commit -m "whoami: remove tutorial app"
git push -u origin tutorial-whoami-cleanup
gh pr create --fill
```

After merging:

```bash
flux reconcile source git ankhmorpork
flux -n flux-system reconcile kustomization apps
kubectl get namespace whoami
```

Once the `apps` Kustomization prunes it, that last command reports
`NotFound`. The namespace, the pod, the certificate and the DNS record all go with
it, because `prune: true` means Flux owns what it created.

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
- **[Explanation](../explanation/index.md)** — why the cluster is arranged this
  way.
