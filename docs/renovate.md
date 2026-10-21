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
  variables on the run step. The CLI version is pinned in that file and bumped by
  Renovate itself through the `custom.regex` manager in `renovate.json5`.
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

`enabledManagers` in `renovate.json5` is the list. Currently `github-actions` (action
versions, plus tool versions set through `setup-*` inputs such as
`terraform_version`, `go-version` and `version` for helm) and `custom.regex` (the CLI
pin above).

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

Renovate needs Node 24. Against a working tree, with no writes anywhere:

```bash
git add -A   # the local platform only sees tracked files, renovate.json5 included
RENOVATE_PLATFORM=local RENOVATE_DRY_RUN=full \
  GITHUB_COM_TOKEN=$(gh auth token) LOG_LEVEL=debug \
  npx --yes renovate
```

The debug log's `branch` fields are the PRs a real run would open.
