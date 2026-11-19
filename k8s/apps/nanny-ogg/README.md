# nanny-ogg

Meal planning on top of Mealie: an Open WebUI instance of its own, plus a proxy
that gives the model a small set of meal-planning tools backed by Mealie's API.
The proxy's code and image live in their own repository; its manifests live
here, next to Open WebUI's.

This directory is the tenant's. `k8s/namespaces/nanny-ogg/` (the Namespace and
the Flux Kustomization that applies this directory) is the platform's. How apps
are laid out, validated and rolled out in general is in
[the app-deployment skill](../../../.claude/skills/app-deployment/SKILL.md) and
[docs/](../../../docs/index.md); this page covers only what is specific here.

## What the cluster provides

| Need | Where | Notes |
| --- | --- | --- |
| Mealie API | `http://mealie.mealie.svc:9000` | Bearer token of the `nanny-ogg` bot user in the household. A token carries its user's full rights, so the bot is not a Mealie admin. |
| LLMs | `http://litellm.ai-gateway.svc:4000/v1` | OpenAI-compatible; a LiteLLM virtual key of its own |
| Login | `https://login.krupa.net.pl/.well-known/openid-configuration` | pocket-id; Open WebUI's callback is `https://<host>/oauth/oidc/callback` |
| Secrets | `ClusterSecretStore/doppler-auth-api` | keys prefixed `NANNY_OGG_`; see below |
| Postgres, if the proxy keeps state | `cnpg-database` chart from `oci://ghcr.io/thaum-xyz/helm-charts` | `k8s/apps/mended-drum/db/` is a working example |
| Backups | K8up, opt-in per PVC | [docs/explanation/app-backups.md](../../../docs/explanation/app-backups.md) |
| `kubectl` | pocket-id group `k8s:group:nanny-ogg` → `edit` on this namespace | [docs/how-to/log-in-with-kubectl.md](../../../docs/how-to/log-in-with-kubectl.md) |

## Secrets

Doppler keys are added by the cluster owner; reference them from an
`ExternalSecret` against `doppler-auth-api`.

| Doppler key | Consumer | Becomes |
| --- | --- | --- |
| `NANNY_OGG_MEALIE_TOKEN` | proxy | Mealie bearer token |
| `NANNY_OGG_LITELLM_KEY` | Open WebUI | `OPENAI_API_KEY` |
| `NANNY_OGG_OIDC_CLIENT_ID`, `NANNY_OGG_OIDC_CLIENT_SECRET` | Open WebUI | `OAUTH_CLIENT_ID`, `OAUTH_CLIENT_SECRET` |

`WEBUI_SECRET_KEY` only has to be stable, so it can be minted in-cluster with a
`Password` generator instead of living in Doppler, as
`k8s/apps/stirling-pdf/oidc-secret.yaml` does for its cookie secret.

For local development, use a separate token of the same bot user against
`https://recipes.krupa.net.pl`, so either can be revoked without the other.

## What the proxy image must do

| Requirement | Why |
| --- | --- |
| Immutable version tags on a public registry, not only `latest` | Renovate bumps the tag in the Deployment here |
| HTTP on one port, answering `GET /healthz` with 200 | liveness/readiness probes |
| Mealie URL and token from environment variables | the token arrives from an `ExternalSecret` |
| Runs as non-root, no privileges | namespace enforces PSA `baseline` |
| Tools over MCP (Streamable HTTP) or an OpenAPI tool server | the two protocols Open WebUI speaks |

Open WebUI calls the proxy from its backend when it is added as an admin
connection, so the proxy needs a `Service` and no `Ingress`. Without one, the
Mealie token behind it is not reachable from outside the cluster.

## Rules the cluster enforces

| Rule | Enforced by | Effect |
| --- | --- | --- |
| Ingress contract (class set, `tls` with `secretName` on `public`/`private`) | `validate-ingress-contract` | **reject** |
| A host reachable from outside needs a `public` **and** a `cloudflare` Ingress | convention | [docs/how-to/expose-an-app.md](../../../docs/how-to/expose-an-app.md) |
| HelmRelease chart version pinned | `validate-helm-chart-version` | **reject** |
| `piraeus-r2-roaming` volumes at most 32Gi | `validate-roaming-volume-size` | **reject** |
| Resource requests set, no CPU limits | `require-resource-requests` (warn), review | CPU limits get removed |
| No Pod runs as `flux-reconciler` | `validate-reconciler-sa-usage` | **reject** |

Full list, generated from the policies:
[docs/reference/admission-policies.md](../../../docs/reference/admission-policies.md).
Storage classes:
[docs/how-to/choose-a-storage-class.md](../../../docs/how-to/choose-a-storage-class.md).
Open WebUI's data volume wants `strategy: Recreate`, and its SQLite files a
consistent dump for backups; `k8s/apps/mended-drum/open-webui/` does both.
