# argo-tag-watcher

Two small in-cluster watchers in one binary. Both notice that a ref moved and poke
the thing that has not caught up: the **git side** refreshes Argo CD Applications
when the deploy tag moves, and the **image side** restarts workloads when a
floating image tag's digest moves.

## Git side -- refresh Argo CD when the deploy tag moves

Argo's periodic resync can quietly stop re-enqueuing Applications, leaving them
`Synced`/`Healthy` but pinned to a stale revision until something pokes them
(symmatree/tiles#667). We deploy from moving `prod`/`test` git tags, so when a tag
moves, nothing reliably triggers a re-check. This watcher is the external poke.

1. Every `INTERVAL`, resolves `WATCH_REF` (e.g. `prod`) to a commit SHA via
   `git ls-remote` (annotated tags are peeled to their commit).
2. When the SHA changes since the last one it converged on, it sets
   `argocd.argoproj.io/refresh=normal` on **every** Application in `ARGOCD_NAMESPACE`,
   in batches of `BATCH_SIZE` with `BATCH_DELAY` between batches (gentle on the
   single repo-server; see tiles#573).

No filtering: refreshing an app that did not change is a cheap no-op, so there is
nothing to gain from guessing which apps "need" it and nothing to miss.

## Image side -- restart workloads when the image digest moves

Some workloads run a **floating** image tag. When that image is rebuilt the tag
string is unchanged, so Argo sees no diff and nothing rolls the workload: it keeps
running the old digest until something restarts it (symmatree/tiles#674).

A restart is disruptive where a refresh is a no-op, so this side does not fan out.
It is **opt in per workload**, and it restarts only the workloads whose digest
actually moved.

1. Every `IMAGE_INTERVAL`, lists Deployments, StatefulSets and DaemonSets in every
   namespace and keeps those annotated
   `tiles.symmatree.com/roll-on-digest-change: "true"`.
2. For each, resolves every container image in the pod template to the digest its
   tag currently points at, anonymously over the registry API.
3. Compares that against the digest the workload's pods actually pulled
   (`status.containerStatuses[].imageID`). Any live pod on a different digest and
   it stamps `kubectl.kubernetes.io/restartedAt` on the pod template, which is
   exactly what `kubectl rollout restart` does.

There is no stored last-seen state: the comparison is registry-versus-reality, so
after the restart the new pod re-pulls, the two match, and it stops.

### What a watched workload needs

- **`imagePullPolicy: Always`.** Without it the replacement pod reuses the cached
  image, the digests never converge and it would restart on every pass.
- **A tag, not a digest.** A digest-pinned image cannot move and is skipped.

### Things it deliberately does not do

- **It will not restart a workload mid-rollout.** A rollout in flight has pods of
  two revisions matching the same selector, so the old ones would read as a reason
  to restart again -- and again. It waits until the controller reports the rollout
  settled, which also means a workload stuck unhealthy is left alone rather than
  restarted in a loop.
- **It ignores terminal pods.** A `Completed` or `Error` pod sticks around holding
  whatever digest it had when it died; the cluster has months-old ones. Comparing
  against those would be a permanent, meaningless mismatch.
- **It carries no registry credentials of its own.** Digest lookups go through
  go-containerregistry with the default keychain, so it authenticates the way any
  container tool does -- from the ambient docker config if there is one,
  anonymously if not. Today's watched packages are public; a private registry
  needs a pull secret mounted and no code change.

### What moves a digest

A rebuild moves the digest whether or not the source changed. The image builds in
this repo (`mavproxy`, `rtkbase`, `mimir-webhook`, this one) run on a nightly
`schedule:` cron as well as on push, so their digests move nightly.
`coordinator-fleet-control` is built by the coordinator repo on pushes that touch
its source, with no cron.

## Config (env)

| var | default | meaning |
|-----|---------|---------|
| `REPO_URL` | `https://github.com/symmatree/tiles.git` | repo to poll |
| `WATCH_REF` | `prod` | ref to watch (`test` on the tiles-test cluster) |
| `ARGOCD_NAMESPACE` | `argocd` | namespace holding the Applications |
| `INTERVAL` | `60s` | git poll period |
| `BATCH_SIZE` | `4` | apps refreshed per batch |
| `BATCH_DELAY` | `5s` | pause between batches |
| `IMAGE_INTERVAL` | `5m` | image digest check period |

## RBAC

The git side is a namespaced Role: `list` + `patch` on `applications.argoproj.io`
in the argocd namespace.

The image side needs a **ClusterRole**, because opted-in workloads live in their
own namespaces: `list` + `patch` on deployments/statefulsets/daemonsets and `list`
on pods, cluster-wide. It cannot create, delete or scale anything. See
`charts/argo-tag-watcher/templates/rbac.yaml`.

The restart annotation is written under the field manager `argo-tag-watcher`.
Argo CD applies these workloads with server-side apply, so the annotation belongs
to a manager Argo does not own and does not read as drift.

## Tests

`go test ./...` (also run by the repo's `test.sh`). All unit tests are offline --
git resolution, the registry and the Kubernetes client are behind interfaces, and
the registry client is exercised against go-containerregistry's in-memory
registry.

## Deployment

Deployed via `charts/argo-tag-watcher/`, wired into the app-of-apps. Its Argo
Application sets `WATCH_REF` from the propagated `targetRevision`, so it watches
whatever tag its cluster deploys from (`prod` / `test`).
