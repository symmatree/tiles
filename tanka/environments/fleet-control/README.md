# fleet-control

Ground-station control surface for the rekon10 fleet: sets up a freshly flashed card and
updates a node that is already set up, over SSH, from a phone. Runs on both clusters.

| | |
|---|---|
| Web UI / API | `https://fleet.{cluster}.symmatree.com` |
| Image | `ghcr.io/symmatree/coordinator-fleet-control:main` |
| Source | [`coordinator/containers/fleet-control`](https://github.com/symmatree/coordinator/tree/main/containers/fleet-control) |
| Tanka | [`main.jsonnet`](main.jsonnet) |
| Argo CD | [`fleet-control-application.yaml`](../../../charts/argocd-applications/templates/fleet-control-application.yaml) |
| Issues | coordinator [#236](https://github.com/symmatree/coordinator/issues/236), [#223](https://github.com/symmatree/coordinator/issues/223) |

The hostname resolves to a private 10.x address on the site LAN; there is no public exposure.

## Before the first sync: the SSH key

The Deployment mounts a private key from 1Password and **will not start without it.** Create
the item before syncing:

| | |
|---|---|
| item | `{cluster}-fleet-ssh-key` in the `{vault}` vault |
| field | `private_key`, holding the PEM private key |

`OnePasswordItem` syncs it to a Secret of the same name, and the `private_key` field is
mounted at `/secrets/ssh/id`.

The matching **public** key must be the `SSH_PUBKEY` in `dotfiles-symm/pi-image/provision/fleet.env`,
so a flashed card trusts it on first boot. Today that is the operator's own key; coordinator
[#261](https://github.com/symmatree/coordinator/issues/261) proposes giving automation its own.

**This credential is root on the whole fleet.** `pi` has passwordless sudo on every node, so
anything that can log in can do anything. That is a property of the fleet, not of this
service, and a dedicated key would make it revocable rather than less powerful.

## The roster

[`inventory.json`](inventory.json) is the source of truth, mounted at `/config/inventory.json`.
Editing it changes the pod-template hash, so Argo rolls the Deployment and the change lands on
the next sync -- no manual step.

`host` is optional and defaults to `name`, so the file carries **names, not addresses**. That
depends on the nodes resolving, which is what [#735](https://github.com/symmatree/tiles/issues/735)
(Terraform-declared UniFi reservations) is for. Until then a node can be pinned by adding
`"host": "10.0.x.y"`, but a DHCP address in git is a temporary measure, not the intent.

```json
{ "name": "campod-se", "role": "campod", "host": "10.0.5.237" }
```

## Storage and lifecycle

- **`/state` (PVC, `local-path`, 1Gi)** holds recorded SSH host keys. Small and rebuildable:
  losing it means the next contact with each node counts as a first contact. `local-path` is
  node-bound, so a node rebuild empties it.
- **`Recreate`, not `RollingUpdate`.** Two replicas could drive the same node at once, and the
  one-action-per-node guard is per process.
- **No liveness probe.** A bootstrap holds run state in memory for around twenty minutes;
  restarting the pod mid-run abandons the remaining steps. Work already started on a node is
  detached and survives, but nothing issues what comes next. Readiness only.

## What it does to a node

| action | runs on the node |
|---|---|
| `bootstrap` | remount `/usr` rw, install git, clone, `./host/one_time.sh <role>`, reboot, `coord pull -q && coord start` |
| `update` | `git pull --ff-only && coord pull -q && coord start` |

The operator chooses; the service does not inspect the node to decide for them. Every action
confirms first, which is a guard against a mis-tap rather than against flying.

The API is the interface and the UI is one client of it:

```sh
curl -sXPOST https://fleet.tiles.symmatree.com/nodes/campod-se/update    # -> 202 {"id": ...}
curl -sN     https://fleet.tiles.symmatree.com/runs/<id>/stream          # live output (SSE)
```

## Auth

None yet. On-network only, like the other private-address services here. If it is ever wanted
remotely it should be fronted with oauth-proxy, per coordinator#223.
