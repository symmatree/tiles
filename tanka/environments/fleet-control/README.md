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
| item | `fleet-ssh-key` in the `tiles-secrets` vault |
| type | 1Password **SSH Key** item |
| field | `private-key` -- hyphen, not underscore |

Unprefixed, because there is one fleet and one key and both clusters read the same vault
(`onepassword_vault_name` is set in `terraform.tfvars`, not per workspace). `ssh_key_secret`
and `ssh_key_field` are parameters -- point them at an item that already exists rather than
copying a key into a new one.

`OnePasswordItem` syncs it to a Secret of the same name, and the named field is mounted at
`/secrets/ssh/id`.

The operator lowercases field labels and replaces spaces with hyphens, so an SSH Key item's
*private key* field becomes `private-key`. [`charts/jupyterhub/values.yaml`](../../../charts/jupyterhub/values.yaml)
consumes `public-key` from its own SSH Key item the same way.

**Unverified, and it cannot be checked before the first sync** -- the `OnePasswordItem` is
created by this environment, so there is no Secret to inspect until it exists. The jupyterhub
precedent only reads the *public* half, so it establishes the hyphen convention but not that
the operator exposes an SSH Key item's private half at all.

So this is deploy-and-look. If the key does not arrive, the pod fails to start or fails to
read `/secrets/ssh/id`, and the fix is one parameter: a different `ssh_key_field`, or the key
in a Secure Note instead. Nothing reaches a vehicle either way -- the service contacts a node
only when an action is requested.

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

Each node takes a `name`, a `role`, and an optional `host` -- an address or a different
hostname -- which defaults to `name`.

```json
{ "name": "coordinator", "role": "coordinator" }
{ "name": "campod-se",   "role": "campod", "host": "10.0.5.237" }
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
