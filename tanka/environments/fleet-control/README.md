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
| Argo CD | [`fleet-control-application.yaml`](../../../charts/argocd-applications/templates/fleet-control-application.yaml) |
| Issues | coordinator [#236](https://github.com/symmatree/coordinator/issues/236), [#223](https://github.com/symmatree/coordinator/issues/223) |

Runs on both clusters.

## Two credentials, both from 1Password

The Deployment mounts a private key and reads a token; **it will not start without the key.**
Both items must exist in the `tiles-secrets` vault before the first sync.

| | item | field | |
|---|---|---|---|
| fleet SSH key | `fleet-ssh-key-managed` (SSH Key) | `private-key` | created by `tf/nodes/fleet-ssh-key.tf`; mounted at `/secrets/ssh/id` |
| GitHub token | `FLEET_GITHUB_TOKEN` (Login) | `password` | *Actions: read-only*, fine-grained |

Unprefixed and shared: there is one fleet, one key, and both clusters read the same vault
(`onepassword_vault_name` is set in `terraform.tfvars`, not per workspace). The item names are
parameters -- point them at an item that exists rather than copying a key into a new one.

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

## Auth

None. On-network only, like the other private-address services here. If it is ever wanted
remotely it should be fronted with oauth-proxy, per coordinator#223.
