# AGENTS.md -- operating rules for this repo

Conduct rules for agents are in [`CLAUDE.md`](CLAUDE.md), whose canonical copy
lives in the `fables` repo. This file is the repo-specific operational layer:
the procedures you must follow rather than reconstruct.

**Read the procedure before you run it.** Every item below is written down
somewhere in this repo. Reading the script and assembling an equivalent command
yourself is how you end up with output that does not match CI, or with a step
skipped that the script would have done.

## Regenerating `rendered.yaml`

`charts/*/rendered.yaml` is committed Helm output and the `build-test` job
compares it **byte for byte**. A values change that does not regenerate it fails
CI on `main` and on every branch cut from `main` afterwards.

```bash
./ci-tools/helm-update-all.sh   # helm dep update --skip-refresh, per chart
./build.sh                      # lint + template every chart, writes rendered.yaml
```

Both, in that order. `build.sh` deliberately does **not** update dependencies
(see its comment) because CI caches them, so running it alone on a clean
checkout stops at the first chart with missing dependencies and renders nothing
after it.

Use the **CI-pinned Helm version**, not whatever is on your PATH. It is the
`helm_version` default in
[`.github/actions/helm-setup/action.yml`](.github/actions/helm-setup/action.yml).
A different minor version produces different bytes and trades one CI failure for
another.

Related: [`docs/caching-strategy.md`](docs/caching-strategy.md) for what the
guarded cache operations are, [`docs/config-propagation.md`](docs/config-propagation.md)
for the placeholder values `build.sh` renders with, and
[`docs/api-versions-strategy.md`](docs/api-versions-strategy.md) for the pinned
API versions it passes.

## Deploying

Argo CD deploys from the moving `test` and `prod` **git tags**, not from `main`,
and Terraform applies the node layer. Neither is a thing to drive by hand from a
reconstructed command line.

- [`docs/environment-strategy.md`](docs/environment-strategy.md) -- the
  tag-based deploy flow and Argo CD's two cache layers, which is why a merge
  takes minutes rather than seconds to appear.
- [`tf/nodes/README.md`](tf/nodes/README.md) -- the **complete** environment
  block for running Terraform locally. There are five `op read` exports, not
  two; a partial set fails partway through, and a partial failure around a state
  mutation leaves declared state and reality out of step.
- [`docs/config-propagation.md`](docs/config-propagation.md) -- how values reach
  a chart through the app-of-apps.

## Charts installed by Terraform

`argocd`, `cilium` and `argocd-applications-installer` are installed by
`helm_release` in `tf/nodes/`, with Argo CD watching and deliberately not
syncing. Argo reporting one of these OutOfSync is not something Argo can fix;
it means Terraform has not applied. See the comments in
[`tf/nodes/k8s-cilium.tf`](tf/nodes/k8s-cilium.tf) and
[`tf/nodes/k8s-argocd.tf`](tf/nodes/k8s-argocd.tf) for the single-writer
arrangement.
