# Renovate

Dependency updates are opened by self-hosted [Renovate](https://docs.renovatebot.com/).
Nothing from Mend is installed on the repository: the Renovate CLI runs directly on
an Actions runner, authenticated as a GitHub App owned by this account.

## Pieces

- [`renovate.json5`](../renovate.json5) -- repository config: which managers are
  enabled, grouping, custom managers.
- [`.github/workflows/renovate.yaml`](../.github/workflows/renovate.yaml) -- runs the
  CLI nightly (1000 UTC) and on `workflow_dispatch`. Global settings (target
  repository, no onboarding PR, config required) are `RENOVATE_*` environment
  variables on the run step. The CLI version is pinned in that file
  (`RENOVATE_VERSION`) and bumped by Renovate itself through the `custom.regex`
  manager in `renovate.json5`. Renovate exits unless the Node it runs on satisfies its
  `engines.node`, so the workflow reads that range for the pinned version with
  `npm view` and gives it to `setup-node`; Node moves to a new major when a Renovate
  release declares support for it.
- The GitHub App and its 1Password item, below.

The CLI runs on the runner rather than in Renovate's container image (as
`renovatebot/github-action` does) so that steps before the run and
`postUpgradeTasks` after an update use the same tool versions CI does -- e.g.
`build.sh` regenerating `charts/*/rendered.yaml` with the helm from
`.github/actions/helm-setup`.

## PR shape

`group:allNonMajor` puts every minor, patch and digest update into one PR
(`renovate/all-minor-patch`); each major update gets its own PR. Renovate keeps
updating the same branches on later runs rather than opening new ones. Every
non-charts PR runs `nodes-plan-apply`, which spends 1Password service-account
reads (#561), so the number of open PRs is the number of CI runs.

The Dependency Dashboard issue lists pending, rate-limited and ignored updates; ticking
a box there makes the next run act on it.

## Enabled ecosystems

`enabledManagers` in `renovate.json5` is the list. Currently:

- `github-actions` -- action versions, plus tool versions set through `setup-*` inputs
  such as `terraform_version`, `go-version` and `version` for helm.
- `custom.regex` -- the CLI pin above.
- `helmv3` -- dependencies in `charts/*/Chart.yaml`. Renovate updates `Chart.lock`
  with the helm installed by `.github/actions/helm-setup`.
- `argocd` -- external charts referenced by the Applications in
  `charts/argocd-applications/templates/`.

For both chart managers a `postUpgradeTasks` entry fetches every chart's dependencies
(`ci-tools/helm-add-repos.sh`, `helm repo update`, `ci-tools/helm-update-all.sh`) and
runs `./build.sh`, committing the regenerated `charts/*/rendered.yaml`. The commands are
allowed by `RENOVATE_ALLOWED_COMMANDS` in the workflow. Renovate's own `Chart.lock`
update reads a fresh repository index, but `helm-update-all.sh` reads the restored helm
cache with `--skip-refresh`, so without the `helm repo update` a chart released after
that day's cache was saved fails `build.sh`.

A failed post-upgrade task is an artifact error. While the newest release in the branch
is under two hours old, Renovate does not open the PR with the error; it aborts the
whole repository run with `Lock file error - aborting` (`result: lockfile-error`), which
leaves the workflow green, opens no PRs and does not update the Dependency Dashboard.
The cause is only in a debug log.

`charts/argocd` and `charts/cilium` are installed by Terraform (`tf/nodes`) from their
local paths, and `helm_release` upgrades only when the chart version changes, so
Renovate bumps those two charts' patch version (`bumpVersion`) with each dependency
update.

Not covered yet: `helm_release` charts in `tf/nodes/k8s-bootstrap.tf`, image tags in
values files.

To add one, add its manager to `enabledManagers`, then run Renovate locally against
a checkout (below) to see what it would open before merging.

## GitHub App

Created by hand under the account's Developer settings (GitHub Apps); no webhook.
Repository permissions, per the
[Renovate GitHub platform docs](https://docs.renovatebot.com/modules/platform/github/):

| Permission | Access |
| --- | --- |
| Administration | read |
| Checks | read and write |
| Commit statuses | read and write |
| Contents | read and write |
| Dependabot alerts | read |
| Issues | read and write |
| Metadata | read |
| Pull requests | read and write |
| Workflows | read and write |

The app is installed on the repositories it updates. Its credentials are in the
1Password item `github-renovate-app` in `tiles-secrets`: the Client ID in a `client-id`
field and the PEM in the item's notes (`notesPlain`), which keeps its line breaks; a
single-line field such as a password collapses them and the key no longer parses
(`ERR_OSSL_UNSUPPORTED`). The workflow reads them with `load-secrets-action` and mints
a one-hour installation token with `actions/create-github-app-token`. Commits and PRs
are authored as the app's `[bot]` user, and pushes with that token trigger the normal
PR workflows (a `GITHUB_TOKEN` push would not).

## Running locally

Renovate needs a Node matching `npm view renovate engines.node`; `npx -p node@24`
supplies one when the installed Node is older. Against a working tree, with no writes
anywhere:

```bash
git add -A   # the local platform only sees tracked files, renovate.json5 included
RENOVATE_PLATFORM=local RENOVATE_DRY_RUN=full \
  GITHUB_COM_TOKEN=$(gh auth token) LOG_LEVEL=debug \
  npx --yes -p node@24 -p renovate renovate
```

The local platform extracts dependencies and looks up updates but processes no
branches, so its debug log lists the available updates and does not run
`postUpgradeTasks`. To run those, dry-run against the repository on GitHub, still with
no writes. Renovate reads the config from the branch named by
`RENOVATE_BASE_BRANCH_PATTERNS`, so a pushed branch's `renovate.json5` can be tried
before it merges:

```bash
RENOVATE_PLATFORM=github RENOVATE_REPOSITORIES=symmatree/tiles \
  RENOVATE_BASE_BRANCH_PATTERNS='["<branch>"]' RENOVATE_USE_BASE_BRANCH_CONFIG=replace \
  RENOVATE_DRY_RUN=full RENOVATE_ONBOARDING=false RENOVATE_REQUIRE_CONFIG=required \
  RENOVATE_ALLOWED_COMMANDS='<as in the workflow>' \
  RENOVATE_TOKEN=$(gh auth token) LOG_LEVEL=debug \
  npx --yes -p node@24 -p renovate renovate
```

`helm-add-repos.sh` needs `yq`.
