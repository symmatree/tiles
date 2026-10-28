# Talos

This repo pins Talos Linux in [tf/nodes/terraform.tfvars](../tf/nodes/terraform.tfvars) (`talos_version`, for example `1.13.0`). Image Factory schematics and ISOs are generated in [tf/nodes/talos-iso.tf](../tf/nodes/talos-iso.tf); installer images are patched in [tf/modules/talos-cluster/nodes.tf](../tf/modules/talos-cluster/nodes.tf).

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

After changing `talos_version`, run Terraform so `proxmox_virtual_environment_download_file` refreshes ISOs and VM CD-ROM references stay consistent.

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
- **Bare-metal rebuild:** Metal workers are not VMs and are not recreated by that flow. A re-apply of unchanged config is a no-op (no reboot), so a rebuild must run with `metal_apply_mode = reboot` or the node stays orphaned on the old etcd. See [bare-metal-nodes.md](bare-metal-nodes.md#rebuilds-metal-reapply--reboot).
- **In-place OS upgrade:** `talosctl -n <node> upgrade --image <install image>`, one node at a time, through the latest patch of each intermediate minor; then `talos_version` is set to the version the nodes run. `--image` is required: talosctl's default is a generic metal installer, not the node's schematic. The install images are `vm_install_image`, `metal_amd_install_image` and `metal_intel_install_image` in [nodes.tf](../tf/modules/talos-cluster/nodes.tf). Kubernetes moves separately, with `talosctl upgrade-k8s --to <version>`, and then `kubernetes_version`. See [Sidero upgrade docs](https://docs.siderolabs.com/talos/v1.14/configure-your-talos-cluster/lifecycle-management/upgrading-talos).
