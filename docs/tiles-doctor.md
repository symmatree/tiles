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

**Build a scratch sandbox rather than shipping a caveat.** "No credentials" is
not "untestable". A question about how a *construct* behaves usually reproduces
offline. `talos_machine_secrets` plus `data.talos_machine_configuration` is local
crypto and rendering only, so a throwaway directory with one pinned provider
version answers "does this provider *render* this config document", with no
cluster and no 1Password. It does not answer whether a node *accepts* it: nodes
validate on apply, and the 1.14 config that rendered cleanly offline was rejected
by every node three times over (see [talos.md](talos.md#machine-config-across-a-provider-minor)).
When the ground truth is the node's behaviour, the apply is the test; do not
build a simulation of it. Image Factory schematic IDs do reproduce exactly: POST
the schematic YAML and compare the returned ID against one already in a plan.

**Answer the question that was asked.** The expensive failure is not being wrong,
it is spending the operator's attention on a question he did not ask -- mechanics
when he asked about sequencing, whether a boolean needs setting when he asked
what the end state should be. He pushes back once; the round is still gone.

**Decisions are surfaced, not announced.** "So I'm setting X" inside a
conversation about X is taking his decision while appearing to report. State the
basis, give a recommendation, and stop. The multiple-choice widget is not a
substitute either -- it reads as asking him to be an oracle without the basis.
Prose, with the evidence and the tradeoff, then wait.

**Ask rather than infer intent.** Write what a change does. The operator's
reasons are theirs to state; inventing a plausible one and recording it as
theirs produces documents that argue against their author.

**Report what you measured, not how much it matters.** Importance, priority and
risk tolerance belong to the operator. A filed issue that opens "not urgent",
closes "rather than work still worth doing", or calls a defect "cosmetic" has
turned a report into a ruling. The same sentence in conversation costs one turn
-- he pushes back and it is gone. In an artifact it persists, and it reaches
every later reader, including the agent he dispatches to work the bug. He
largely does not re-read issues he asked you to file, which is exactly why this
is the wrong place to put a verdict. The tells are grading adjectives (*small*,
*minor*, *trivial*, *cosmetic*), priority stamps (*not urgent*, *low priority*),
worth-judgments (*worth doing*, *worth a fresh look*), and directives aimed at a
future implementer (*should not be carried forward*). Give the number and what
it is a number of. If importance needs settling, settle it in conversation,
where he can answer.

**A bug is an intention, not a diff.** Dispatch here means handing an agent the
issue and asking it to review the real state and form its own conclusions. Detail
written from a shallow pass is not neutral in that flow -- it is a conclusion the
next reader anchors on, reached with less context than they will have, and it
does the analysis twice. Capture the requirement and the facts that are *wrong*
elsewhere; leave the design, the file list and the implementation order to
whoever picks it up. Related: a bug is not a living document. Two of three parts
done is a comment saying so, not a retitle around the survivor.

## Traps

| Trap | Check |
|---|---|
| Local git tags are stale; `git fetch --tags` will not move an existing tag | `git fetch --tags --force`; trust `git ls-remote` over `git rev-parse` when they disagree |
| A query window's first data point is not the retention edge | Probe retention separately before concluding "no data before X" |
| Argo deploys from the `test`/`prod` tags, not `main` | A merge is not a deploy; check the tag, then the live object |
| `rendered.yaml` is committed Helm output that CI compares byte-for-byte | Regenerate with the CI-pinned helm version; `build.sh` stops at the first chart with missing deps |
| Grafana, Mimir and the alerting all run on the cluster they monitor | During an incident the instrument may be the thing that is down |
| `CLAUDE.md` links to `philosophy/guiding-principles.md`, which is not in this repo | It lives in the fables repo: `~/facts/fables/philosophy/guiding-principles.md` |
| A terraform plan shows `(known after apply)` instead of your new value | Anything downstream of an unknown (a schematic ID) cannot appear in the plan; read the branch, not the plan, to confirm an input landed |
| The Talos **Terraform provider** vendors its own `pkg/machinery` | That copy, not `talos_version`, fixes which config document kinds parse and what `kubernetes_version` defaults to. See [talos.md](talos.md) |
| A Loki query on an unindexed label scans zero bytes and returns nothing | Identical to "logged nothing". `pod` is structured metadata: ``{ns="x"} \| pod=`y` `` works, `{ns="x", pod="y"}` silently does not. See [notebooks.md](notebooks.md) |
| `tf/nodes` applies **prod** on push to `main` | PR runs are plan-only (`refresh: false`). A merge is a production apply, so sequence live work before the merge, not after |
| A VM's in-place `talosctl upgrade` | The VMs boot from the CD-ROM first, so a host cold boot (host-maintenance, Mon-Fri 01:00 America/New_York) puts them back on the attached ISO's version until `talos_version` is applied. See [talos.md](talos.md#upgrading-talos) |
| `talosctl upgrade` drains with `Force` | Pods with no controller are deleted, including JupyterHub singleuser servers -- and this session, when the node is lancer |
| A drain fails on `pod-eviction-mimir.grafana.com` | `mimir-rollout-operator` serves that webhook and was itself evicted; re-run once it is `Running` elsewhere |
| A control-plane node is rebooting and the API times out | Expected until it is back. Calls to the control plane in that window fail and add load; start one passive watcher and wait |
| An etcd member is listed but its applied index has stopped | It does not count for quorum in practice; upgrading another control-plane node then loses quorum |
| A chained `[ a ] && [ b ]` under `set -e` | Does not stop the script when `a` fails; write stop conditions as `if ...; then exit 1; fi` |
| A chart dependency bump inside `charts/argocd` (or any Terraform-installed wrapper chart) plans as "No changes" | `helm_release` diffs on its arguments; bump the wrapper chart's own `version` in the same PR |
| A `valuesObject` map (e.g. a chart's `node_selector`) | Helm merges maps with the chart default instead of replacing them; set an unwanted default key to `null` (amd-gpu: both PCI labels became required, DaemonSet desired 0) |
| A PR that bumps a `crd-charts` version | `publish-crd-charts` and `nodes-plan-apply` start together; the plan can fail with `not found` before the push lands. Re-run the plan |
| A controller upgrade (Argo CD, cert-manager, Cilium, ...) | Its CRDs come only from `ci-tools/crd-charts/sources.yaml`, not the chart; bump them first. Before a CRD bump, check live `status.storedVersions` are still served. Gateway API v1.6 TLSRoute serves only `v1`, which crashed the Cilium 1.19 operator until 1.20 landed |
| Argo shows `ComparisonError ... field not declared in schema` | Argo CD's bundled `k8s.io/api` is older than the cluster's; upgrade Argo CD |
| A StatefulSet's storage changes (`volumeClaimTemplates`) | Immutable: Argo's sync fails, and auto-sync stops retrying the revision after 5 attempts. `kubectl delete sts --cascade=orphan`, then a sync, then roll pods one at a time |
| A manual Argo sync via `operation` | Does not inherit `syncPolicy.syncOptions`; pass `CreateNamespace=true,ServerSideApply=true` explicitly. Client-side apply fails on the large Mimir dashboard ConfigMaps (annotation > 256 KiB) |
| `synology_container_project` (Container Manager on raconteur) | Renders services into compose `content` that is not marked sensitive and is printed in full when an apply fails -- keep secrets in compose `secrets`. An in-place update can fail to build on DSM (email "Cannot build project") while Terraform reports success, leaving the old container; `replace_triggered_by` on a `terraform_data` of the service and cert, plus the password, forces replacement |
| Mimir's `filesystem` storage backend over NFS | Fails from Mimir 3.2 (objstore writes a `user.thanos.objstore.sha256sum` xattr; raconteur is NFS 4.1, kernel 4.4). Prod Mimir now uses S3 on versitygw on raconteur (`tf/nodes/synology-versitygw.tf`) |
| `ubuntu-latest` moves | It became 26.04; `wg-quick` then refused a config in `$HOME`. The action writes `/etc/wireguard/wg0.conf` |
| A Renovate PR's render-diff comment | Truncated at GitHub's comment limit; run `scripts/render-apps-diff.sh` on the branch locally for the full diff |
| A new `app_of_apps_values` key reaches the Helm release but not the root Application | `charts/argocd-applications-installer/templates/application.yaml` lists the propagated keys by hand; add the key there too, and bump that chart's `version` -- `helm_release` diffs on its arguments, so a template-only edit plans as no changes. Terraform shows no diff for the missing key either and `build.sh` renders children from `values.yaml`, so only the live root app fails (`.Values.X is required` in its ComparisonError) |

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

- [`AGENTS.md`](../AGENTS.md) -- the build and deploy procedures, including the
  two commands that regenerate `rendered.yaml` and why running `build.sh` alone
  renders nothing past the first chart with missing dependencies. Read it rather
  than reassembling the commands from the scripts.
- [`build.sh`](../build.sh) and [`scripts/helm-common.bash`](../scripts/helm-common.bash)
  -- how `rendered.yaml` is produced and which flags are applied.
- [`render-diff.md`](render-diff.md) -- `scripts/render-apps-diff.sh`, the offline
  render of every Application before and after a change; run it locally before
  committing anything under `charts/` or `tanka/`.
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
- **The Proxmox hosts**: `ssh root@<host IP>` (the hosts are in `~/.ssh/known_hosts`
  by IP, not name; this pod's key is not authorised, the root password is in
  `~/proxmox.txt`). `qm config <vmid>` for a VM's boot order and CD-ROM.

## In flight (2026-11-06)

Snapshot at handoff; check each against the live system before acting.

- **acebase down** since ~2026-11-05 17:00Z: no route to `10.0.128.53`; telemetry flat to 16:58Z, logs stop with no shutdown sequence. Needs someone at the machine; then `talosctl -n acebase dmesg`. mavproxy, mavproxy-mlrs and rtkbase are down with it.
- **Mimir ruler memory**: ~930 MiB (was 126-143 MB daily max) since the 2026-11-01 22:08Z rollout, against a 128 Mi request; it pushed tiles-wk-1 into memory pressure on 11-02. Cause not established (Mimir 3.2.3, or rule queries now succeeding against long-term storage).
- **`MimirStrongConsistencyOffsetMissing`**: caused by the ruler's internal evaluation (strong reads, no query-frontend, so no offsets). Seth agreed to drop it; the chart has no per-alert switch. Open choice: a `mimir-mixin` Tanka environment with `alertsToDrop` (and `mimirAlerts: false`), or an Alertmanager route to nothing.
- **Mimir leftovers**: the NFS mount `mimir-shared-storage` and the `mimir-mimir-data` PV/PVC are unused since #928; 80 partial blocks from the outage should be deleted by the compactor after `compactor_partial_block_deletion_delay: 1d`. tiles-test Mimir still uses the filesystem backend.
- **versitygw**: why Container Manager failed the in-place build at 2026-11-01 18:40Z is unknown (Container Manager > Log on raconteur).
- **Grafana** to a `cluster-nfs` PVC (#766): deferred by Seth; needs `/var/lib/grafana` copied (the `grafana-mcp` service account exists only there).
- **postgres-operator**: `ComparisonError` / `SyncError`, `.configuration.enable_maintenance_windows: field not declared in schema` (chart config vs installed CRD).
- **static-certs-sync-unifi** job failed on 2026-11-05; not looked at.
- **flight-analysis** nightly CronJob failing since 2026-10-30 (flight-analysis-guy's).
- **lancer GPU** (#581): `amd.com/gpu: 1` advertised; no workload has used it yet.
- **cp-1's etcd secretbox key** was printed into this session's transcript on 2026-10-29; rotating it is Seth's call.
