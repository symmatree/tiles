# fleet-control

Ground-station control surface for the rekon10 fleet: converge a node, reimage one, read what
each is running, and pull a flight's captures off the cards -- from a phone, over SSH, driven
from the cluster.

**What the service is and does is documented with the service**, in
[`coordinator/containers/fleet-control/README.md`](https://github.com/symmatree/coordinator/tree/main/containers/fleet-control)
-- the routes, the one action, the image and the run log. That is where it changes, so that is
where it is described; **this file is the deployment only.** A copy of it here goes stale
without anyone noticing, which is exactly what happened: this README described `bootstrap` and
`update` actions running `./host/one_time.sh` for months after
[coordinator#263](https://github.com/symmatree/coordinator/pull/263) replaced both with one
`converge` and deleted the script.

| | |
|---|---|
| Web UI / API | `https://fleet.{cluster}.symmatree.com` -- a private **10.x** address on site LAN, no public exposure |
| Image | `ghcr.io/symmatree/coordinator-fleet-control:main` |
| Source | [`coordinator/containers/fleet-control`](https://github.com/symmatree/coordinator/tree/main/containers/fleet-control) |
| Tanka | [`main.jsonnet`](main.jsonnet), settings in [`application.yaml`](application.yaml) |
| Argo CD | [`fleet-control-application.helm.yaml`](../../../charts/argocd-applications/templates/fleet-control-application.helm.yaml) (prod only) |
| Issues | coordinator [#236](https://github.com/symmatree/coordinator/issues/236), [#223](https://github.com/symmatree/coordinator/issues/223) |

Prod (`tiles`) only: it converges the fleet, and the fleet SSH key has exactly one writer.

## Two credentials, both from 1Password

The Deployment mounts a private key and reads a token; **it will not start without the key.**
Both items must exist in the `tiles-secrets` vault before the first sync.

| | item | field | |
|---|---|---|---|
| fleet SSH key | `fleet-ssh-key-managed` (SSH Key) | `private-key` | created by `tf/nodes/fleet-ssh-key.tf`; mounted at `/secrets/ssh/id` |
| GitHub token | `FLEET_GITHUB_TOKEN` (Login) | `password` | *Actions: read-only*, fine-grained |

Unprefixed: there is one fleet and one key, and `onepassword_vault_name` comes from
`terraform.tfvars` rather than per workspace, so the name is not qualified by cluster and must not
be written from more than one place -- see `tf/nodes/fleet-ssh-key.tf`. The item names are
parameters: point them at an item that exists rather than copying a key into a new one.

The operator lowercases field labels and replaces spaces with hyphens, which is why an SSH Key
item's *private key* field arrives as `private-key`. The 1Password *title* `FLEET_GITHUB_TOKEN`
is not a legal Kubernetes object name (DNS-1123: lowercase, no underscores), so the item path
keeps the title and the object gets a derived one.

**The SSH key is root on the whole fleet.** `pi` has passwordless sudo on every node, so
anything that can log in can do anything. That is a property of the fleet, not of this service;
coordinator [#261](https://github.com/symmatree/coordinator/issues/261) proposes giving
automation its own revocable key. The **token is not**: it can fetch published build artifacts
and nothing else, and every route except the image fetch works without it.

The matching **public** key must be `SSH_PUBKEY` in `dotfiles-symm/pi-image/provision/fleet.env`,
so a freshly flashed card trusts it on first boot.

## The roster

[`inventory.json`](inventory.json) is the source of truth, mounted at `/config/inventory.json`.
Editing it changes the pod-template hash annotation, so Argo rolls the Deployment and the change
lands on the next sync -- no manual step.

Each node takes a `name`, a `role`, and an optional `host` (an address or a different hostname)
defaulting to `name`. The `host` values are current DHCP leases and need updating when one
moves; [#735](https://github.com/symmatree/tiles/issues/735) makes them reservations, after
which the names resolve and `host` can come out. `campod-ne` and `campod-nw` are listed without
one because they have not been flashed.

## Volumes

| mount | claim | why that class |
|---|---|---|
| `/state` | 1Gi, `local-path` | recorded SSH host keys. Small and rebuildable -- losing it makes the next contact with each node a first contact. Node-bound, so a node rebuild empties it |
| `/images` | 20Gi, `cluster-nfs` | disk images the service has pushed (coordinator [#312](https://github.com/symmatree/coordinator/issues/312)). **Not** `local-path`: that would pin the pod to one node and die with it. ~24 images at 813 MiB, nothing evicting |
| `/mnt/flights` | 2Ti, static NFS PV, `Retain` | where recovered flights land. `FLEET_FLIGHTS_DIR` points at `/mnt/flights/rekon10`, the platform level, because the service joins only the flight name it is given and `flight-data-layout.md` is `flights/<platform>/<flight>/`. A static PV because the datasets share (`datasets_nfs_path`, per cluster) is a different export from the one `cluster-nfs` provisions into, so a dynamic claim cannot reach it -- same pattern and subpath as `flight-analysis` and `vio-offline`. `Retain`, because this holds the only copy of a flight once the device is wiped |

The image runs as `node` (uid/gid 1000) and Secret volumes are root-owned, so `fsGroup: 1000`
is what makes the 0440 key readable by the process that needs it.

## Lifecycle

- **`Recreate`, not `RollingUpdate`.** Two replicas could drive the same node at once, and the
  one-action-per-node guard is per process.
- **No liveness probe.** A converge holds state in memory for twenty minutes or more, and
  restarting the pod mid-run abandons the remaining steps -- the work already on the node
  survives, but nothing issues what comes next. Readiness only.
- **`roll-on-digest-change: true`**, opting in to
  [argo-tag-watcher](../../../containers/argo-tag-watcher/README.md)'s image side. The image is
  a floating `:main` tag, so a rebuild moves the digest without changing the string here and
  nothing would otherwise roll the pod. That matters more here than elsewhere: **the ansible
  playbook is baked into this image**, so a stale pod converges nodes with a playbook that is
  not the one on `main`.

## Converges run as Argo Workflows

[coordinator#504](https://github.com/symmatree/coordinator/issues/504). The service runs
`ansible-playbook` as a subprocess of itself today; this is the deployment side of moving it
into a pod of its own. Nothing submits one yet.

The objects are a `WorkflowTemplate` (`fleet-control-converge`), a ServiceAccount for the
workflow's pods, and two Roles.

### Why a template rather than a Workflow built in code

A `WorkflowTemplate` is a definition, so it is reviewable in git; what the service submits is
a reference to it plus parameters. That is only possible because the Argo CRDs are installed
by `tf/nodes/k8s-bootstrap.tf`, ahead of the Argo CD tree — Argo CD cannot diff a resource
whose type it does not know. See [#827](https://github.com/symmatree/tiles/issues/827).

The step's body is `run-playbook.sh` out of the service's own image. Whether that script
belongs in that image is an open question; moving it changes `image` and `command` here and
nothing else.

### Why in this namespace

Everything a converge needs is already here: the fleet key, the GitHub token, the roster.
Running workflows in a central namespace would mean a second copy of the fleet key in a
second namespace, and one key with two homes is how this service came to present a key no
device trusted.

`FLEET_SSH_PUBLIC_KEY` is the `public-key` field of the **same 1Password item** that holds
`private-key`; `charts/jupyterhub` consumes its own ssh-key item the same way. Terraform
generates the pair and writes both fields together.

### Why two Roles

| Role | grants | to |
|---|---|---|
| `fleet-control-workflow` | `workflowtaskresults` create, patch | the workflow's **pods** |
| `fleet-control-submit` | `workflows` create/get/list/watch/delete, `pods` + `pods/log` read | the **service** |

Argo's executor reports each step's outcome by writing a `workflowtaskresult`, so a pod needs
that much. This is why a namespace that runs workflows carries a little RBAC of its own
rather than inheriting the controller's, which is cluster-wide and comes with the chart.

The service's half is submitting and then finding its workflow again — **by label, not by an
id held in memory**, so that a pod roll does not orphan a workflow that is still running.
That is the property the whole change exists to buy.

In Kubernetes terms the workflow pod is nearly unprivileged: two verbs on one resource. Its
reach comes from the mounted fleet key, which is root on every device.

### No `activeDeadlineSeconds`

Deliberate. A previous version of the service imposed a 60-minute ceiling, hit it on a slow
node, and reported a successful converge as a failure while the play was still running.
Killing a play half-way leaves a part-configured box. Ansible's own timeouts bound it.

### `ttlStrategy: 7 days`

There is no workflow archive ([#831](https://github.com/symmatree/tiles/pull/831)), so the
`Workflow` object *is* the run record and this is how far back the API can answer "what ran".
The log outlives it either way: Alloy ships the step's stdout to Loki.

### Not on lancer

Same as the Argo Workflows controller itself. lancer's taint is `PreferNoSchedule`, so
omitting the toleration is only a hint — the `nodeAffinity` is what holds.

## Auth

None. On-network only, like the other private-address services here. If it is ever wanted
remotely it should be fronted with oauth-proxy, per coordinator#223.
