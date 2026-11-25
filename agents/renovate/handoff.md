# Handoff: renovate

For whoever is the renovate session next. Read it at the start; update it at the end
of a session, as a PR, not during.

Durable facts about Renovate graduate to [docs/renovate.md](../../docs/renovate.md);
work graduates to issues. What stays here is what would otherwise be dropped: open
threads not yet worth an issue, and the state of things in progress.

## Punch list

- **Conduct link.** `~/.claude/CLAUDE.md` should link to `~/dotfiles-symm/agents/conduct.md`
  (dotfiles-symm `install.sh` does it). As of 2026-11-25 the link did not exist yet.
  tiles#991, coordinator#760 and fables#36 slim each repo's CLAUDE.md to repo
  specifics and should merge only once it does; otherwise role sessions lose the
  conduct rules. Check `ls -la ~/.claude/CLAUDE.md` first thing.
- **`facts/CLAUDE.md`** still calls `fables/CLAUDE.md` the canonical conduct doc.
  After fables#36 that is wrong. facts is Seth's archivist repo; raise it, do not edit.
- **Seed memories.** New roles get `memory/` copied by hand from
  `~/facts/claude-memories/<repo>/memory` -- a seed, not a shared or synced store.
  The tiles one is pruned to an empty index (everything went to `conduct.md`,
  `workspace.md` or tiles docs). `dotfiles-symm` (22) and `coordinator` (~89) are not
  pruned yet; the same pass, when Seth bootstraps roles from them, saves that role
  the work. Several dotfiles-symm names look already covered by `conduct.md`
  (`peers-do-not-speak-for-seth`, `no-invented-critic`) -- unread, so unverified.
- **Renovate reports green when it aborts.** A repository-level abort
  (`result: lockfile-error`, `exitCode: 7` in the log) still ends the workflow
  `success`. The quick health check is
  `gh run view <id> --log | grep -o '"result": "[^"]*"'` -- `done` is healthy. Whether
  to make the job fail on it is Seth's call; not raised yet.
- **Coverage gaps** from docs/renovate.md: `helm_release` charts in
  `tf/nodes/k8s-bootstrap.tf`, image tags in values files.

## State

- Renovate is healthy as of 2026-11-25: the 19:51Z run was `result: done`, opened
  #987 (argo-cd, k8s-monitoring, loki, renovate), all checks green, merged. The fix
  was #986 (`helm repo update` before the post-upgrade dependency fetch); the failure
  mode is written up in docs/renovate.md.
- GitHub repos managed by `tf/bootstrap` merge with merge commits now (#988, applied).
  Branches merged after that are ancestors of `main`; `git branch -d` works on them.
  Older branches merged by rebase still need `-D`.

## Notes

- **Scheduled workflows start 7-12 hours late.** Measured 2026-11-25 from run
  creation times: the 10:00 UTC Renovate cron started between 17:17 and 21:58 over
  the prior week. pre-commit's cron has been unchanged since Nov 2025, yet its start
  times drifted from about 1h late in July 2026 to about 5h in September, 6-7h in
  October and 8-12h in November. The order between workflows holds. No source for
  the cause.
- **Debugging Renovate:** the info log hides everything useful. docs/renovate.md has
  the read-only dry run against GitHub, and `RENOVATE_BASE_BRANCH_PATTERNS` plus
  `RENOVATE_USE_BASE_BRANCH_CONFIG=merge` runs a pushed branch's `renovate.json5`
  before it merges -- that is how #986 was verified. The local platform processes no
  branches, so it cannot test `postUpgradeTasks`. The pod has Node 22;
  `npx -p node@24 -p renovate@<ver> renovate` covers it. `yq` is not installed here.
- **The 2-hour rule** (Renovate `update/branch/index.js`): with artifact errors, a
  branch whose newest release is under 2h old aborts the whole run rather than
  opening the PR. The `renovate` package itself releases several times a day, so a
  group that includes it is often inside that window -- any artifact error in the
  group then looks like an outage rather than a PR with an error comment.
- **Working with Seth.** Seth reviews and merges fast, often mid-turn: query PR state
  right before saying anything about it. A "no" to an extension of a request is not a
  "no" to the part already asked for and done. GitHub settings are Terraform in
  `tf/bootstrap`; never `gh api` them. When Seth asks a design question ("would merge
  be better?"), answering with the mechanism and the measurement, then the concrete
  diff, went well.
- **Session layout.** Role CLAUDE.md imports load at start; a non-home checkout's
  CLAUDE.md loads only once a file in it is read. Anything that must be known from
  the first turn has to be imported.
