# Why a database failover interrupts an app { .quad-explanation }

Every CloudNativePG cluster here publishes a `<name>-rw` Service, and every app
that writes connects through it. That Service selects on a **label the operator
moves**, not on a fixed pod:

```yaml
selector:
  cnpg.io/cluster: postgres
  cnpg.io/instanceRole: primary
```

During a switchover the old primary's label is removed before the new primary's
is applied. For that moment no pod carries `instanceRole: primary`, so the
Service has **no endpoints at all**. This is deliberate: a write must not reach
a demoted primary, and having nowhere to go is the safe failure.

The cost is that clients see a hard failure rather than a pause.

## The error text is misleading

With no endpoints behind the Service, Cilium answers with EHOSTUNREACH, which
Go's dialer prints as:

```
dial tcp 10.43.5.207:5432: connect: no route to host
```

That reads like a broken network, and it is not. It is a label transition
completing normally. The same wording also appears here for genuine datapath
problems, so the two are easy to conflate — the way to tell them apart is
whether the timestamp lines up with `Requesting fast shutdown` and
`I'm the target primary` in the cluster's own logs.

An app that reports `no route to host` against a `-rw` Service is almost always
reporting a failover, not a network fault.

## Two ways an app can respond

The window is short. What decides whether it is a blip or an outage is entirely
the client.

| The app… | Result |
| --- | --- |
| retries the connection | a few failed queries, no visible downtime |
| exits the process | downtime for as long as the restart takes |

Most things in this cluster do the first. They are not configured to; it is
simply what a normal connection pool does when a socket dies.

An app that does the second turns routine database maintenance into an outage,
and there is nothing to tune on the database side that will save it — see the
pgbouncer result below. `k8s/apps/pocket-id/postgres/values.yaml` records one
such app and what was tried for it.

The failure is worse than a single restart when the app also holds a lease or
lock in that same database. It dies without releasing it, and the restarted
process is then locked out by its own stale entry until the lease expires — so
one failover costs two or more restarts.

## What shortens the window

`primaryUpdateMethod` decides how the operator replaces a primary when the
cluster's image or configuration changes:

| Value | What happens | Window |
| --- | --- | --- |
| `restart` (the operator's default) | Postgres stops and starts in place on the primary | as long as a Postgres restart |
| `switchover` | an already-running replica is promoted | as long as a label change |

`switchover` is the shorter of the two and is the better default for anything
with a real availability target. It shortens the window; it does not close it,
because either path passes through the same no-endpoint moment. Which clusters
set it is in their `values.yaml`.

## pgbouncer does not close it

A connection pooler in front of the database looks like the obvious fix: let
pgbouncer hold the client connection and re-establish the backend one. In
transaction pool mode that is genuinely what it does — between transactions a
client is not bound to any particular backend.

It was tried for pocket-id and measured with a deliberate `cnpg promote` on
2026-09-09. A 7-second switchover produced about 88 seconds of downtime and four
restarts through the pooler, against roughly two restarts connecting directly.
It was reverted.

Two reasons, and the first is not tunable:

1. **The pooler cannot prevent the first failure.** While the `-rw` Service has
   no endpoints, pgbouncer has no backend either. Transaction pooling lets a
   client survive a backend swap only when there is a backend to swap to.
   Anything that would have failed talking to Postgres directly still fails.
2. **It then slows recovery down.** pgbouncer caches a failed server login for
   `server_login_retry` and answers *new* client connections with
   `FATAL: server login has been failing` for that period. An app that exits and
   restarts into that window fails during startup, so its crash loop outlives
   the switchover that started it.

Setting `server_login_retry` to zero addresses the second point and not the
first, which leaves the pooler no better than a direct connection while adding
two more pods and a `requiredDuringScheduling` anti-affinity to satisfy.

A pooler is still worth having for what it is actually for — bounding backend
connection counts for an app that opens many. It is not failover tolerance.

## What actually fixes it

The client has to retry. That is a property of the application, so for
third-party software it is an upstream change rather than a configuration one,
and the honest local options are to shorten the window with `switchover` and to
schedule maintenance when an interruption is acceptable.

This is also why the reboot gate waits for the CloudNativePG alerts to be quiet
before draining a node — see [how a node reboot is gated](node-reboots.md).
