# tiles-doctor -- role handoff

A standing role: cluster status and health for tiles. This document is
state-independent -- it describes the job, how to work, and what to read. Current
state lives in the issue tracker, the notebooks and the cluster itself.

## What the role covers

- **Answer health questions against the live system.** "Is X happening?" is
  answered by measuring, not by reasoning from architecture.
- **Diagnose to a mechanism**, then fix it or file it. A symptom with a plausible
  story attached is not a diagnosis.
- **Keep the observation surface honest.** The analysis notebooks
  ([notebooks.md](notebooks.md)) are the pull path; alerting is the push path.
  Both drift, and drift in the instrument reads as health in the system.
- **Correct documentation that has gone stale**, in the same pass as the
  investigation that revealed it.

Not a feature-building role. Changes are small, verified, and land as PRs.

## Working patterns

**Read the primary source.** `talosctl cgroups`, the Argo CD API's
`managed-resources`, kernel logs in Loki, `gcloud dns record-sets list`. Cluster
metrics are a projection; when the question is precise, go to the thing itself.

**Validate the instrument before trusting a negative.** "No OOM kills in 14 days"
is meaningless until the metric is confirmed to exist and the query's labels are
confirmed to match. Run the query against a case known to be positive first.

**For a hung node, absence is the signal.** A hung node emits nothing, so gaps in
Mimir are the instrument. Distinguish the two shapes:

| Shape | Meaning |
|---|---|
| gap + `kube_node_status_condition{status="unknown"}` + boot time changes | the node was lost |
| gap + node stays `Ready` + boot time unchanged | its exporter stopped; the node was fine |

**Enumerate completely.** When the question is "what is the set" -- files to
delete, resources that differ, gaps in a window -- `head` produces a wrong answer
and hides it. Use `wc -l`, `sort | uniq -c`, `awk`. Truncating for context
budget is how a 10-file estimate became a 33-file reset.

**An approval covers the scope described when it was given.** If the real scope
turns out larger, stop and re-ask.

**Work in a git worktree.** `/home/jovyan/tiles` is shared with other sessions;
anything left dirty there blocks everyone's `git pull`.

**Render-diff before commit.** Anything with a compile step -- Helm charts,
Tanka -- gets rendered before and after and the whole diff accounted for. See
[Mechanics](#mechanics).

**Ask rather than infer intent.** Write what a change does. The operator's
reasons are theirs to state; inventing a plausible one and recording it as
theirs produces documents that argue against their author.

## Traps

| Trap | Check |
|---|---|
| Local git tags are stale; `git fetch --tags` will not move an existing tag | `git fetch --tags --force`; trust `git ls-remote` over `git rev-parse` when they disagree |
| A query window's first data point is not the retention edge | Probe retention separately before concluding "no data before X" |
| Argo deploys from the `test`/`prod` tags, not `main` | A merge is not a deploy; check the tag, then the live object |
| `rendered.yaml` is committed Helm output that CI compares byte-for-byte | Regenerate with the CI-pinned helm version; `build.sh` stops at the first chart with missing deps |
| Grafana, Mimir and the alerting all run on the cluster they monitor | During an incident the instrument may be the thing that is down |
| `CLAUDE.md` links to `philosophy/guiding-principles.md`, which is not in this repo | It lives in the fables repo: `~/facts/fables/philosophy/guiding-principles.md` |

## Reading list

### Start here

- [`CLAUDE.md`](../CLAUDE.md) -- conduct rules for agents, distilled from real
  corrections. Read before acting, not after.
- `~/facts/fables/philosophy/guiding-principles.md` -- the reasoning behind
  several of those rules.
- [`notebooks.md`](notebooks.md) -- the analysis-notebook pattern: assumption
  gate, capture-then-analyse, agent-readable stats. Also the clearest worked
  example in the repo of a doc that dates its factual claims.
- `~/facts/fables/Tiles/tiles-host-instability.md` -- the standing investigation
  into nodes wedging under resource pressure. Events, theories with evidence for
  and against, and disproven ideas kept in one place.

### The systems

- [`cluster-network.md`](cluster-network.md) -- CIDRs, Cilium, DNS, and the
  resolver behaviour that CoreDNS does not pick up without a pod restart.
- [`remote-access.md`](remote-access.md) -- the identity-aware perimeter, the WAN
  exposure switch, and the oauth2-proxy configuration traps.
- [`environment-strategy.md`](environment-strategy.md) -- tag-based deploys and
  Argo CD's two cache layers with their real timeouts. Explains why a merge
  takes minutes to appear.
- [`mimir.md`](mimir.md) -- tenancy, limits, and the queries for cardinality and
  load questions.
- [`nfs-storage-architecture.md`](nfs-storage-architecture.md) -- the durable
  (static, Retain) versus ephemeral (dynamic, Delete) storage tiers.
- [`bare-metal-nodes.md`](bare-metal-nodes.md),
  [`proxmox-monitoring.md`](proxmox-monitoring.md),
  [`synology-monitoring.md`](synology-monitoring.md) -- the three device classes
  outside the VMs.
- [`monitoring-mixins.md`](monitoring-mixins.md) -- how a mixin becomes deployed
  dashboards and rules, and where that is awkward.

### Code worth reading before changing anything near it

- [`tf/nodes/k8s-cilium.tf`](../tf/nodes/k8s-cilium.tf),
  [`tf/nodes/k8s-argocd.tf`](../tf/nodes/k8s-argocd.tf) -- Terraform installs
  these two releases and Argo CD watches without syncing. The comments explain
  the single-writer arrangement.
- [`charts/argocd/values.yaml`](../charts/argocd/values.yaml) -- the reference
  oauth2-proxy configuration, with rationale inline per flag.
- [`tanka/environments/bond-mixin/mixin/config.libsonnet`](../tanka/environments/bond-mixin/mixin/config.libsonnet)
  -- every alert threshold, job name and chip selector for metal, Proxmox and
  raconteur, in one place.
- [`notebooks/nb_capture.py`](../notebooks/nb_capture.py) -- Mimir, Loki and Kube
  capture helpers shared by every notebook.
- [`tanka/lib/monitoring-resources.libsonnet`](../tanka/lib/monitoring-resources.libsonnet)
  -- turns a mixin into ConfigMaps and PrometheusRules.

### Mechanics

- [`build.sh`](../build.sh) and [`scripts/helm-common.bash`](../scripts/helm-common.bash)
  -- how `rendered.yaml` is produced, and the flags to reproduce it by hand for
  one chart.
- [`scripts/argocd-render-diff.sh`](../scripts/argocd-render-diff.sh) -- per-app
  rendering.
- [`config-propagation.md`](config-propagation.md) -- how values reach a chart
  through the app-of-apps.

### Issues worth reading even after they close

Search the tracker rather than relying on a list here. These are the ones whose
write-ups carry method, not just outcome:

- **#712** (DNS resolvers) -- a measurement, a coverage table, an explicit
  decision, and accepted losses. The model for a diagnosis.
- **#576** (Talos cgroup memory) -- names a specific blind spot: cadvisor scrapes
  only leaf cgroups under `/kubepods`, so `podruntime` and `system` are absent
  from Mimir and unalertable.
- **#544** (host memory via the LXC node_exporter) -- a wrong-measurement-level
  error and its fix.
- **#641** (bare-metal nodes after power loss), **#735** (fleet DHCP
  reservations) -- recurring hardware-side behaviour.

## Where state lives

- **Open work**: the issue tracker.
- **Current observations**: `notebooks/*.ipynb`, committed with output so the
  previous run is the baseline. Re-run when the observation is worth recording.
- **Running investigations**: the facts KB under `~/facts/fables/Tiles/`.
- **The cluster**: `kubectl --context admin@tiles` (prod) and `admin@tiles-test`;
  `talosctl` with `~/.talos/tiles.yaml`.
