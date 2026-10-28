# Talos

This repo pins Talos Linux in [tf/nodes/terraform.tfvars](../tf/nodes/terraform.tfvars) (`talos_version`; current values in [Versions that must move together](#versions-that-must-move-together)). Image Factory schematics and ISOs are generated in [tf/nodes/talos-iso.tf](../tf/nodes/talos-iso.tf); installer images are patched in [tf/modules/talos-cluster/nodes.tf](../tf/modules/talos-cluster/nodes.tf).

## Image Factory and installer URL shape

Terraform uses the **installer** image (not the legacy `nocloud-installer/` path). The value written into machine config looks like:

```text
factory.talos.dev/installer/<SCHEMATIC_ID>:v<TALOS_VERSION>
```

- `<SCHEMATIC_ID>` comes from `talos_image_factory_schematic.vm.id` (Proxmox VMs), `metal_amd.id` (bare-metal AMD), or `metal_intel.id` (bare-metal Intel).
- `<TALOS_VERSION>` matches `talos_version` in tfvars (no leading `v` in tfvars; URLs use `v` prefix as above).

VM schematic includes the `qemu-guest-agent` system extension and kernel args such as `net.ifnames=0` and `-talos.halt_if_installed`. See `talos-iso.tf` for the exact YAML passed to Image Factory.

## ISO and disk images

Proxmox nodes download a **nocloud** ISO per Talos version and schematic, for example:

```text
https://factory.talos.dev/image/<SCHEMATIC_ID>/v<TALOS_VERSION>/nocloud-amd64.iso
```

The VMs boot `order=ide2;scsi0;net0` (CD-ROM first), so after a cold start a VM runs the attached ISO's Talos version, with its config and data from disk. The ISO is therefore what keeps a VM on `talos_version` across a Proxmox host reboot; an in-place `talosctl upgrade` lasts only until the VM's next cold boot unless the ISO matches. A `talos_version` change replaces each host's `proxmox_download_file`: the old ISO is deleted before the new one downloads, and the download is fetched by the Proxmox host from factory.talos.dev (it has failed with HTTP 596, `Connection timed out`; re-running the job succeeded).

## Versions that must move together

Three versions are coupled, and only two of them are visible in tfvars:

| What | Where | Current |
|---|---|---|
| Talos OS on the nodes | `talos_version` in [terraform.tfvars](../tf/nodes/terraform.tfvars) | 1.14.5 |
| Kubernetes | `kubernetes_version` in the same file | 1.36.0 |
| The config shape and the `kubernetes_version` default | `siderolabs/talos` provider pin in [.terraform.lock.hcl](../tf/nodes/.terraform.lock.hcl) | 0.12.0 |

The Talos **Terraform provider** vendors its own copy of Talos `pkg/machinery`, and that
copy -- not `talos_version` -- decides which config document kinds parse and what
`kubernetes_version` defaults to. Provider 0.11.0 carries machinery 1.13.0; 0.12.0 carries
1.14.0. So a `talos_version` bump across a minor needs the provider bumped with it, or the
nodes run a Talos release whose config kinds the provider cannot generate or validate.

`kubernetes_version` is pinned rather than defaulted because the provider's default follows
its vendored machinery (1.37.0 for provider 0.12.0), not the version the cluster runs.
Pinning keeps a provider bump from moving Kubernetes as a side effect; Kubernetes moves
with `talosctl upgrade-k8s` and then a `kubernetes_version` change.

## talosctl

Use a **talosctl** build that matches the cluster Talos version (same minor line as nodes). Always pass `--talosconfig` explicitly; see [secrets.md](secrets.md#talos-client-configuration-talosconfig) and [dev-setup.md](dev-setup.md).

## Bare metal

Bare-metal installers and ISO URLs use **metal** schematics: `metal_amd` (AMD) and `metal_intel` (Intel). Outputs `metal_amd_iso_url` and `metal_intel_iso_url` in `tf/nodes/`. See [bare-metal-nodes.md](bare-metal-nodes.md).

## Upgrading or rebuilding clusters

- **VM replace:** Destroy targeted `proxmox_virtual_environment_vm` resources and `terraform apply` (see [README.md](../README.md#recreating-cluster)).
- **Bare-metal rebuild:** Metal workers are not VMs and are not recreated by that flow. A re-apply of unchanged config is a no-op (no reboot), so after a rebuild each metal worker is rebooted with `talosctl reboot`, or it stays orphaned on the old etcd. See [bare-metal-nodes.md](bare-metal-nodes.md#rebuilds-metal-reapply--reboot).
- **In-place OS upgrade:** see [Upgrading Talos](#upgrading-talos).

## Upgrading Talos

Each upgrade is different; read the release notes of every version crossed. The procedure below is the one that took the cluster from 1.13.0 to 1.14.5 (2026-10-27/28, [#774](https://github.com/symmatree/tiles/issues/774), [#849](https://github.com/symmatree/tiles/pull/849)).

### Before starting

- **Hops.** Upstream: *"always upgrade to the latest patch release of all intermediate minor releases"* ([Sidero upgrade docs](https://docs.siderolabs.com/talos/v1.14/configure-your-talos-cluster/lifecycle-management/upgrading-talos)). Every node moves to one hop before any node moves to the next, so a hop is a wave across all eight nodes.
- **Kubernetes compatibility.** `pkg/machinery/compatibility` gives each Talos minor's Kubernetes range (1.13: 1.31.0-1.36.99; 1.14: 1.32.0-1.37.99). `talosctl upgrade` does not move Kubernetes; a Kubernetes version outside the older Talos's range waits until every node is on the newer one.
- **etcd.** The etcd image follows the Talos version (not pinned in config): 1.13.12 ships 3.6.14, 1.14.5 ships 3.7.3. An etcd minor change has its own rules -- 3.7 requires every member on 3.6.11 or later first -- and a snapshot beforehand: `talosctl -n tiles-cp-1 etcd snapshot <path>`. The snapshot holds every Secret; delete it once the upgrade is done.
- **Provider.** Crossing a Talos minor needs the provider bump in the same change; see [Versions that must move together](#versions-that-must-move-together).
- **Images.** Install images are `factory.talos.dev/<installer|metal-installer>/<schematic>:v<version>`, one per schematic (VM, AMD metal, Intel metal; IDs from the plan or `terraform output`). Check each returns HTTP 200 from the registry before starting.
- **Client.** `talosctl` at the target version.
- **Host maintenance.** The [host-maintenance](../tanka/environments/host-maintenance/README.md) CronWorkflows reboot one Proxmox host a night (01:00 America/New_York, Mon-Fri), which cold-boots that host's VMs onto their ISO. Between the first VM upgrade and the merge that swaps the ISOs, that reverts the VMs on that host.

### Per node, one at a time

```text
talosctl -n <node> upgrade --image <install image>
```

Then confirm before the next node: `Ready`, `osImage` at the new version, not cordoned, and `talosctl -n tiles-cp-1,tiles-cp-2,tiles-cp-3 etcd status` showing three members, no learners, no errors, and each member's applied index equal to its raft index.

- **Drain.** `talosctl upgrade` drains with `Force`, so pods with no controller are deleted, not rescheduled -- including JupyterHub singleuser servers (and any session running in one) on that node.
- **Mimir.** `pod-eviction-mimir.grafana.com` is served by `mimir-rollout-operator`; if the drain evicts the operator, the drain's other Mimir evictions fail on the webhook and the upgrade aborts before installing. Re-run once the operator is `Running` elsewhere.
- **Control-plane nodes.** A control-plane reboot can move the API VIP (10.0.128.10). The API was unreachable through the VIP for ~17 minutes during one cp-1 reboot, with Talos OOM kills on the 3 GB cp-2; talosctl's own wait and uncordon can fail in that window while the upgrade succeeds, so check the node afterwards and uncordon if needed. Talos-API calls to the control plane during the reboot fail or time out and add load.
- **A stalled etcd member.** A member whose applied index stops advancing still counts toward the member list. With one such member, upgrading another control-plane node leaves one working member and loses quorum; restart (upgrade) the stalled one first and confirm it caught up.
- **Pull time.** Installer pulls from factory.talos.dev have ranged from seconds to over 15 minutes per node; `--timeout` defaults to 30m.

### After the last node

1. Set `talos_version` (and the provider pin, for a minor) and merge. The apply replaces the ISOs, swaps each VM's CD-ROM, and re-applies machine config. In `auto` mode no node rebooted for the 1.14 config.
2. Kubernetes, if moving: `talosctl -n tiles-cp-1 upgrade-k8s --to <version> --dry-run`, then without `--dry-run`, then `kubernetes_version` in its own PR.

### Machine config across a provider minor

An offline render (`data.talos_machine_configuration`, `talosctl gen config`) does not show whether a node accepts the config; the node validates it on apply. The 1.14 config was rejected by every node until:

- no patch set a v1alpha1 field that a 1.14 document replaces (`machine.install` vs `UnattendedInstallConfig`, `cluster.clusterName` vs `KubeClusterConfig`, `cluster.network` vs `KubeNetworkConfig`);
- `KubeAPIServerConfig`, `KubeControllerManagerConfig`, `KubeSchedulerConfig` and `KubeProxyConfig` went only to control-plane nodes ([talos-config-controlplane.yaml](../tf/modules/talos-cluster/talos-config-controlplane.yaml));
- the install disk selector moved into the same patch as the install image: machinery before 1.14.5 (provider 0.12.0 bundles 1.14.0) clears a CEL expression that a later patch omits ([siderolabs/talos 03075319b](https://github.com/siderolabs/talos/commit/03075319b)).

Talos 1.14 also refuses the `REBOOT` apply mode (`please use AUTO or NO_REBOOT modes instead`).
