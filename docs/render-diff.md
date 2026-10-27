# Render diff: what a change does to the deployed manifests

`scripts/render-apps-diff.sh` renders every Argo CD Application for both clusters
twice -- from the merge base and from the working tree -- and diffs the results per
app. The `render-diff` workflow runs it on every PR that touches `charts/`, `tanka/`
or the cluster tfvars and posts one comment per cluster. Locally it is the
render-diff-before-commit step for anything under those paths.

It needs no cluster, VPN or secret. Everything it reads is in the repo.

## Why two stages

Most changes here are not to a chart. They are to the **app-of-apps**: an
`app_settings` value, a `valuesObject` key or a `valueFiles` entry in
`charts/argocd-applications/templates/<app>-application.yaml`. Rendering the chart
that owns the workload cannot see those, and rendering `argocd-applications` only
shows the Application CR changing, not what the change does to the workload.

So the render follows the same path Argo CD does:

1. **Roots.** `charts/argocd-applications-installer` and `charts/argocd-applications`
   are rendered with the real propagated values (below). The output of the second
   is the list of Application CRs for that cluster -- the templates gate on
   `cluster_name`, so prod and test produce different lists.
2. **Children.** Each Application CR is read back and rendered from the source it
   names, with the values it names:

   | Application source | rendered with |
   |---|---|
   | `plugin` (Tanka CMP) | `tk show environments/$TK_ENV --ext-str ARGOCD_APP_PARAMETERS=<plugin.parameters as JSON>`, in `tanka/`, after `jb install` -- the same command as `generate.sh` in `charts/argocd/templates/tanka.yaml` |
   | `path` to a chart in this repo | `helm template <app> <path>` after `helm dependency build` when there is a `Chart.lock` |
   | `chart` from a Helm repository | `helm template <app> <chart> --repo <repoURL> --version <targetRevision>` |

   Helm options honoured, in Argo CD's merge order: `valueFiles` (relative to the
   source path, or `$values/<repo path>` for a multi-source app), then
   `valuesObject`; `skipCrds` (otherwise `--include-crds`, which is Argo CD's
   default); `releaseName` (default: the app name); `destination.namespace`.
   `helm.parameters`, `helm.values`, `helm.fileParameters`, `kustomize` and
   `directory` are not implemented and fail the app's render if they appear.

A change to an Application's inputs therefore shows up as a change in that app's
rendered manifests, which is the thing worth reviewing.

## Where the values come from

Terraform passes `module.cluster.app_of_apps_values`
([`tf/modules/talos-cluster/main.tf`](../tf/modules/talos-cluster/main.tf)) into the
installer; see [config-propagation.md](config-propagation.md). The renderer rebuilds
that set from the same inputs Terraform reads, so no second copy of the cluster
config exists:

- the **key list** is `charts/argocd-applications-installer/values.yaml`, the
  declared propagated set;
- each key's **value** is the quoted scalar of the same name in
  `tf/nodes/terraform.tfvars` then `tf/nodes/{prod,test}.tfvars`, falling back to the
  variable's `default` in `tf/nodes/variables.tf`;
- three keys are not plain variables and are mapped in the script: `cluster_name`
  (the argument), `targetRevision` (`prod` for `tiles`, `test` otherwise, as
  `local.target_revision`), `vault_name` (`onepassword_vault_name`).

A key with no value and no default fails the render. Adding a propagated value to
the installer therefore means giving it a tfvars value or a default, which is also
what Terraform needs.

Secrets are never values here: every secret is a 1Password reference resolved in the
cluster, so the rendered output is safe to post on a PR.

## What it does not cover

- **Charts Terraform applies directly** -- Cilium's bootstrap release, the Argo CD
  release, the CRD charts and the installer itself
  ([`tf/nodes/k8s-*.tf`](../tf/nodes/)). `nodes-plan-apply` plans those on every PR
  and shows the `helm_release` inputs changing, not the rendered manifests. The
  installer chart is also rendered here, as `argocd-applications-installer.yaml`,
  because it is a local chart with the same values. The Terraform side is a separate
  mechanism and is meant to stay one.
- **The cluster's real API surface.** Both sides render with the pinned
  `--kube-version` and `--api-versions` from `charts/extract-apis/`
  ([api-versions-strategy.md](api-versions-strategy.md)), as `build.sh` does. Argo
  CD renders against the live API server; a chart that branches on an API version
  not in that list renders differently here.
- **Image digests.** A floating tag such as `rtkbase:main` renders as the same
  string before and after a rebuild. That is `argo-tag-watcher`'s problem
  ([`containers/argo-tag-watcher/README.md`](../containers/argo-tag-watcher/README.md)),
  not this one.
- **Live drift.** This compares two renders of git, not a render against the
  cluster. `argocd app diff` does the latter, from a workstation on the VPN.

## Running it

```bash
scripts/render-apps-diff.sh                 # against origin/main, both clusters
CLUSTERS=tiles scripts/render-apps-diff.sh  # one cluster
TXT_OUTPUT_DIR=/tmp/rd scripts/render-apps-diff.sh some-branch
```

Output is `render-diff-<cluster>.txt` in `TXT_OUTPUT_DIR` (default
`/tmp/txt-outputs`): a summary of which apps changed with added/removed line counts,
then the unified diffs. The working tree is rendered as it stands, uncommitted edits
included. One cluster takes about 40 s per side on a workstation; CI runs both
clusters, both sides, in a few minutes.

`scripts/render-apps.sh <cluster> <outdir> [repo_root]` is the one-sided render,
useful on its own for reading what an app currently deploys. A failed render leaves
`<app>.ERROR` holding the renderer's stderr instead of `<app>.yaml`, and the diff
shows that file appearing.

Tools: helm (the CI-pinned version, see
[`.github/actions/helm-setup/action.yml`](../.github/actions/helm-setup/action.yml)),
`yq` (mikefarah), `tk` and `jb`. CI pins `tk` to the version the CMP runs
(`charts/argocd/templates/tanka.yaml`) so the render is the one Argo CD produces.

## Relation to `rendered.yaml`

`build.sh` renders each local chart alone with placeholder values and commits the
result as `charts/*/rendered.yaml`; `build-test` fails if it is stale. That is a
lint of the chart in isolation and a committed snapshot. This is the other half:
the chart as deployed, with the real values, for every app including the ones whose
chart lives in a Helm repository and the Tanka environments -- none of which have a
`rendered.yaml`. Nothing here is committed; the PR comment is the artifact.
