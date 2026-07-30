# Pre-render + sentinel-swap: a spike

**Status: proof-of-concept, nothing here is wired into the live deploy path.**
This directory is a self-contained demonstration of one way to get Argo CD out of
the business of rendering ~30 apps at sync time, without checking Terraform
outputs into git. It exists so we can look at a working thing and decide, not so
it can be adopted as-is.

## The problem it targets

Today every child app is rendered at sync time by the repo-server (Tanka CMP or
Helm). That renderer is a single throttled pod (`reposerver.parallelism.limit:
"2"`), and Tanka generation is slow and serialized (per-generation `jb install` +
vendor copy under a global `flock`; see `charts/argocd/templates/tanka.yaml`).
Because `prod`/`test` are moving tags, every promotion invalidates the manifest
cache for all apps at once and stampedes that one renderer, so apps drift to stale
SHAs and "need a manual refresh." (Observed 2026-07: apps on the same `prod` tag
synced to four different commits, some not reconciled in days.)

## The idea

Structure has to be resolved by a real renderer (jsonnet/Helm). But **scalar leaf
values can be deferred to a post-render string substitution** -- and every value
that is genuinely unknown until `terraform apply` is a scalar. In tiles that set
is essentially one value, `project_id` (`random_project_id = true` in
`tf/bootstrap/gcp-projects.tf`); it appears only as a leaf (an external-dns
`--google-project=` arg, a cert-manager ClusterIssuer `project:` field, a Tanka
`--ext-str`), never in a way that changes structure. Everything else that varies
is a Terraform *input* (`cluster_name`, CIDRs, `seed_project_id`, ...), known
before apply.

So:

1. **CI pre-renders** each app per cluster (`scripts/render-app.sh`). Inputs are
   baked; the one generated output, `project_id`, is emitted as the sentinel
   `@@TILES_PROJECT@@`. The slow/fragile renderer runs here, in parallel, once.
2. **Terraform applies** the real `project_id` into the cluster (via the narrow
   app-of-apps root it already owns) -- live, no intermediary, so it can't lag.
3. **At sync**, a trivial CMP (`rendered-sub-cmp.yaml`) does a literal token
   replace `@@TILES_PROJECT@@` -> real `project_id`. No jsonnet, no `tk show`, no
   flock; a sub-second `sed`. The stampede-prone renderer is gone from the sync
   path.

The sentinel neutralizes the **lag** objection: the committed/published artifact
holds a placeholder, never a real post-apply value, so it is never a generation
behind Terraform. Terraform stays the live source of the real value.

## Proof it's lossless

`scripts/prove-roundtrip.sh` renders each app with the sentinel, `sed`s it back to
a real value, and diffs against a direct render with that real value. Identical
output means `project_id` really is a pure leaf and the swap loses nothing; a leak
would fail loudly here instead of shipping a wrong manifest.

```
PASS  external-dns     sentinel(sed)->real == direct-render   (sentinels=1)
PASS  cert-manager     sentinel(sed)->real == direct-render   (sentinels=2)
```

`rendered/external-dns.yaml` (the arg case) and
`rendered/cert-manager-issuers-excerpt.yaml` (the CRD-field case) are committed so
the sentinel placement is inspectable. The cert-manager excerpt shows the
distinction in one view: `project: "@@TILES_PROJECT@@"` (generated output,
deferred) right next to `project: "seed-example"` (input, baked).

## Honest edges (what still needs a decision)

- **git vs OCI is a separate question from lag.** The sentinel fixes lag for the
  generated *output*. But the pre-rendered artifact also bakes Terraform *inputs*
  (CIDRs, nfs paths, cluster domain) -- non-secret, but the kind of config tiles
  currently keeps out of git and in 1Password. If that principle holds, publish
  the artifact to **OCI**, not a git branch. (This demo uses fake inputs precisely
  so nothing real is committed.)
- **Per-cluster render is required.** Inter-cluster values differ *structurally*
  (e.g. loki's `tiles` values add a `resources:`/`singleBinary:` block that
  `tiles-test` omits), so you cannot render once and string-sub `cluster_name`.
- **The swap must be a literal token replace, never `envsubst`.** Rendered configs
  are full of legitimate `${...}` (Alloy/Loki/Mimir, shell scripts). The sentinel
  has no `$` and cannot collide.
- **Tanka apps aren't covered here.** `render-app.sh` handles single-source Helm
  apps. Tanka envs render the same way in principle (`tk show` with the sentinel
  as `--ext-str project_id`), but that path isn't built in this spike.
- **Not wired live.** No repo-server sidecar, no Application rewrite. Flipping one
  app is a small follow-up once the approach is agreed.

## Files

| file | what |
|------|------|
| `../../scripts/render-app.sh` | CI pre-render: app-of-apps -> child valuesObject -> chart, with sentinel |
| `../../scripts/prove-roundtrip.sh` | the lossless-round-trip check above |
| `example-inputs.yaml` | per-cluster inputs shape (fake values; real ones come from 1Password in CI) |
| `rendered/` | committed example renders (sentinel visible) |
| `rendered-sub-cmp.yaml` | the sync-time swap CMP + how an Application flips to it |
