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

## talosctl

Use a **talosctl** build that matches the cluster Talos version (same minor line as nodes). Always pass `--talosconfig` explicitly; see [secrets.md](secrets.md#talos-client-configuration-talosconfig) and [dev-setup.md](dev-setup.md).

## Bare metal

Bare-metal installers and ISO URLs use **metal** schematics: `metal_amd` (AMD) and `metal_intel` (Intel). Outputs `metal_amd_iso_url` and `metal_intel_iso_url` in `tf/nodes/`. See [bare-metal-nodes.md](bare-metal-nodes.md).

## Upgrading or rebuilding clusters

- **VM replace:** Destroy targeted `proxmox_virtual_environment_vm` resources and `terraform apply` (see [README.md](../README.md#recreating-cluster)).
- **Bare-metal rebuild:** Metal workers are not VMs and are not recreated by that flow. A re-apply of unchanged config is a no-op (no reboot), so a rebuild must run with `metal_apply_mode = reboot` or the node stays orphaned on the old etcd. See [bare-metal-nodes.md](bare-metal-nodes.md#rebuilds-metal-reapply--reboot).
- **In-place OS upgrade:** Upstream procedure uses `talosctl upgrade` with the same installer image as in machine config; this repo usually drives version via Terraform and full VM refresh. See [Sidero upgrade docs](https://docs.siderolabs.com/talos/v1.13/configure-your-talos-cluster/lifecycle-management/upgrading-talos).
