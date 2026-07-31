# argo-tag-watcher

A tiny in-cluster controller that makes Argo CD notice git changes without a manual
refresh.

## Why

Argo's periodic resync can quietly stop re-enqueuing Applications, leaving them
`Synced`/`Healthy` but pinned to a stale revision until something pokes them
(symmatree/tiles#667). We deploy from moving `prod`/`test` git tags, so when a tag
moves, nothing reliably triggers a re-check. This watcher is the external poke.

## What it does

1. Every `INTERVAL`, resolves `WATCH_REF` (e.g. `prod`) to a commit SHA via
   `git ls-remote` (annotated tags are peeled to their commit).
2. When the SHA changes since the last one it converged on, it sets
   `argocd.argoproj.io/refresh=normal` on **every** Application in `ARGOCD_NAMESPACE`,
   in batches of `BATCH_SIZE` with `BATCH_DELAY` between batches (gentle on the
   single repo-server; see tiles#573).

No filtering: refreshing an app that did not change is a cheap no-op, so there is
nothing to gain from guessing which apps "need" it and nothing to miss. It checks
once on startup, which converges any drift accumulated while it was down.

## Config (env)

| var | default | meaning |
|-----|---------|---------|
| `REPO_URL` | `https://github.com/symmatree/tiles.git` | repo to poll |
| `WATCH_REF` | `prod` | ref to watch (`test` on the tiles-test cluster) |
| `ARGOCD_NAMESPACE` | `argocd` | namespace holding the Applications |
| `INTERVAL` | `60s` | poll period |
| `BATCH_SIZE` | `4` | apps refreshed per batch |
| `BATCH_DELAY` | `5s` | pause between batches |

## RBAC

Least privilege: `list` + `patch` on `applications.argoproj.io` in the argocd
namespace, nothing else. See `deploy/argo-tag-watcher.yaml`.

## Tests

`go test ./...` (also run by the repo's `test.sh`). All unit tests are offline —
git resolution and the Kubernetes client are behind interfaces and faked, so no
network or cluster is touched.

## Not in this PR

- Not wired into the app-of-apps; going live means building the image and either
  `kubectl apply`-ing `deploy/` or converting it to an Argo Application whose
  `valuesObject` sets `WATCH_REF` from the propagated `targetRevision`.
- The image side (watch a floating image tag's digest, `rollout restart` opted-in
  workloads) is a planned follow-up; the two share the "notice the ref moved, poke
  the thing" shape but a restart is disruptive so it checks the digest per workload.
