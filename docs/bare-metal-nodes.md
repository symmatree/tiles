# Bare-Metal Talos Nodes (AMD)

This document describes how **bare-metal** Talos workers fit into the Tiles Terraform layout. **Source of truth:** [tf/nodes/talos-iso.tf](../tf/nodes/talos-iso.tf), [tf/nodes/cluster.tf](../tf/nodes/cluster.tf), [tf/modules/talos-cluster/nodes.tf](../tf/modules/talos-cluster/nodes.tf), and [tf/modules/talos-metal/main.tf](../tf/modules/talos-metal/main.tf). Do not copy Image Factory schematic IDs from docs; they change whenever `talos_version` or schematic YAML changes. Use `terraform output` or the Terraform plan for current values.

Tiles pins `talos_version` in [tf/nodes/terraform.tfvars](../tf/nodes/terraform.tfvars) (for example the **1.13** release line). Where this doc points at Sidero Labs documentation, links use the matching **v1.13** docs so CLI flags, kernel parameters, and install behavior line up with that version.

## What is already implemented

### Two Image Factory schematics

In `tf/nodes/talos-iso.tf`:

1. **`talos_image_factory_schematic.vm`** -- Proxmox / **nocloud** images with `qemu-guest-agent` and VM-oriented kernel args (`vga=792`, `net.ifnames=0`, `-talos.halt_if_installed`).
2. **`talos_image_factory_schematic.metal_amd`** -- **metal** images with `amd-ucode`, `amdgpu`, `amdgpu-firmware` and `net.ifnames=0`, `-talos.halt_if_installed`.

Terraform outputs include `vm_schematic_id`, `metal_amd_schematic_id`, and `metal_amd_iso_url`.

### Wiring into the cluster module

[tf/nodes/cluster.tf](../tf/nodes/cluster.tf) passes `talos_vm_schematic` and `talos_metal_amd_schematic` into `module.cluster`. [tf/modules/talos-cluster/nodes.tf](../tf/modules/talos-cluster/nodes.tf) sets:

- `vm_install_image` = `factory.talos.dev/installer/${vm_schematic}:v${talos_version}` for `module.talos-vm`
- `metal_amd_install_image` = `factory.talos.dev/metal-installer/${metal_schematic}:v${talos_version}` for `module.talos-amd-metal`

The VM image uses the generic `installer/` path; bare metal uses `metal-installer/` for the platform-specific installer (see [Image Factory](https://docs.siderolabs.com/talos/v1.13/learn-more/image-factory) and [Boot assets](https://docs.siderolabs.com/talos/v1.13/platform-specific-installations/boot-assets)). [talos.md](talos.md) summarizes installer URL shape for VMs.

Patches merge [talos-config.yaml](../tf/modules/talos-cluster/talos-config.yaml), cluster CIDRs, the correct `machine.install.image`, optional **Layer2VIPConfig** on control plane nodes only, and optional kubelet taints.

### Metal module behavior

[tf/modules/talos-metal/main.tf](../tf/modules/talos-metal/main.tf) does **not** create a Proxmox VM. It:

1. Registers the MAC in UniFi (fixed IP, local DNS name).
2. Runs `talos_machine_configuration_apply` against the node IP.

The host must already be running Talos (maintenance mode from ISO/USB/PXE, or installed) so the Talos machine API is reachable on the node IP (default TCP **50000**). Booting from a Talos ISO does not install to disk until machine configuration is applied; see the upstream [bare-metal ISO](https://docs.siderolabs.com/talos/v1.13/platform-specific-installations/bare-metal-platforms/iso) guide for that behavior.

### When bare-metal resources run

`module.talos-amd-metal` is keyed by `metal_amd_nodes` ([tf/nodes/variables.tf](../tf/nodes/variables.tf)). Workspace tfvars (`test.tfvars`, `prod.tfvars`, etc.) currently set `metal_amd_nodes = {}`. Adding a worker means adding an entry to that map and applying Terraform.

## Onboarding an AMD bare-metal worker

1. **Cluster must exist** -- Bootstrap comes from control plane VMs. Metal is an extra worker (or future control plane if you extend the module and roles).
2. **Pick IP and MAC** -- Align with your cluster network doc and UniFi; the metal module creates the UniFi client.
3. **Add `metal_amd_nodes`** in the right workspace tfvars, for example:

   ```hcl
   metal_amd_nodes = {
     rising = {
       name        = "tiles-wk-rising"
       type        = "worker"
       mac_address = "xx:xx:xx:xx:xx:xx"
       ip_address  = "10.0.x.x"
       taint       = "" # or a taint key if you use dedicated= taints
     }
   }
   ```

4. **Boot the machine** from the **metal** ISO for the current `talos_version` (see `metal_amd_iso_url` output or URL pattern below).
5. **`terraform apply`** -- Applies machine config to the node IP once the Talos API is up.
6. **Verify** -- Node joins Kubernetes; use `talosctl` / `kubectl` as in [secrets.md](secrets.md) and [dev-setup.md](dev-setup.md).

First-time apply from maintenance mode may use `talosctl apply-config --insecure` if certificates are not yet established; see the Talos [getting started](https://docs.siderolabs.com/talos/v1.13/getting-started/getting-started) flow for your boot phase.

## Why VM and metal schematics differ

- **qemu-guest-agent** is for virtual machines only; it is not used on bare metal.
- **AMD Ryzen APU** class nodes use microcode and `amdgpu` / `amdgpu-firmware` [system extensions](https://docs.siderolabs.com/talos/v1.13/build-and-extend-talos/custom-images-and-development/system-extensions) for integrated graphics firmware paths. The same extension set is documented for Phoenix-class APUs in fleet notes; adjust the extension list in `talos-iso.tf` if you add different hardware.

**NPU / Ryzen AI:** There is no separate Talos system extension for the XDNA NPU. GPU-oriented stacks (ROCm, operators) run as cluster workloads, not as Talos extensions.

**Intel bare metal:** The repo only defines **`metal_amd`** today. Intel would need a parallel schematic data source + resource (same pattern as `metal_amd`) and a new module or `for_each` branch if you add it.

## ISO, installer, and PXE URL patterns

Replace placeholders from Terraform outputs or plan. For generic bare-metal install context (not Tiles-specific), see Talos v1.13 [ISO](https://docs.siderolabs.com/talos/v1.13/platform-specific-installations/bare-metal-platforms/iso) and [PXE](https://docs.siderolabs.com/talos/v1.13/platform-specific-installations/bare-metal-platforms/pxe) guides and [Image Factory](https://docs.siderolabs.com/talos/v1.13/learn-more/image-factory).

- **Metal ISO:** `https://factory.talos.dev/image/<METAL_AMD_SCHEMATIC>/v<TALOS_VERSION>/metal-amd64.iso`
- **Installer image (machine config, bare metal):** `factory.talos.dev/metal-installer/<METAL_AMD_SCHEMATIC>:v<TALOS_VERSION>`
- **PXE (example):** `https://pxe.factory.talos.dev/pxe/<METAL_AMD_SCHEMATIC>/v<TALOS_VERSION>/metal-amd64`

`TALOS_VERSION` in URLs uses the `v` prefix (e.g. `v1.13.0-beta.1`); `terraform.tfvars` uses the same string without `v` (e.g. `1.13.0-beta.1`).

## Kernel arg: `-talos.halt_if_installed`

Schematics set `-talos.halt_if_installed` so boot media can act as installer and recovery: the installer can hand off to an existing disk install unless you interrupt during the timeout. The v1.13 kernel parameter reference documents [`talos.halt_if_installed`](https://docs.siderolabs.com/talos/v1.13/reference/kernel); see Talos release notes for behavior differences across patch releases. Background on ISO boot handoff is in [Talos issue #10090](https://github.com/siderolabs/talos/issues/10090).

Bare-metal workers get `machine.install.image` from `metal_amd_install_image` in [tf/modules/talos-cluster/nodes.tf](../tf/modules/talos-cluster/nodes.tf), which uses the `metal-installer` path (not the VM `installer` image).

## Operational commands

Use the talosconfig for the right cluster ([secrets.md](secrets.md#talos-client-configuration-talosconfig)). For `talosctl reset` flags (`--graceful`, `--reboot`, `--system-labels-to-wipe`), see [Resetting a machine](https://docs.siderolabs.com/talos/v1.13/configure-your-talos-cluster/lifecycle-management/resetting-a-machine/) (Talos v1.13).

```bash
talosctl --talosconfig ~/.talos/tiles.yaml reset --reboot --graceful=false --nodes <NODE_IP>
```

- **`reset`:** Wipes disk and reboots; often used before reinstall.
- **Maintenance without full disk wipe:** Use `talosctl reset` with `--system-labels-to-wipe EPHEMERAL` and `--system-labels-to-wipe STATE` (and `--reboot`); there is no `talosctl reboot --mode maintenance`. See the example in the next section.

**Graceful vs not:** `--graceful=false` skips draining workloads (faster, more disruptive).

## Coordinating with VM lifecycle

If you destroy Proxmox VMs in Terraform while touching bare metal, run order and downtime matter. See [README.md](../README.md#recreating-cluster) for VM destroy targets. Bare metal resets often take longer to boot than VMs; plan accordingly.

**Optional automation:** You can wrap `talosctl reset` in `null_resource` + `local-exec`, but that hides failures in Terraform state and can surprise you on every apply if triggers are too broad. Manual or scripted steps outside Terraform are easier to reason about for rare cluster rebuilds.

## Remote management and USB / PXE

The previous long-form guidance still applies in principle:

- **USB ISO:** Write the metal ISO from the URL above; set boot order appropriately.
- **PXE:** Serve kernel/initramfs or iPXE script from Image Factory URLs with the current schematic and version; the upstream [PXE](https://docs.siderolabs.com/talos/v1.13/platform-specific-installations/bare-metal-platforms/pxe) guide covers generic metal PXE boot and required kernel parameters.

If the node is running but you want to reinstall without wiping the whole disk first, you can wipe only the EPHEMERAL and STATE partitions so the node reboots into maintenance mode (and will then boot from USB/ISO if that is first in boot order):

```bash
talosctl --talosconfig ~/.talos/tiles.yaml reset --system-labels-to-wipe EPHEMERAL --system-labels-to-wipe STATE --reboot --graceful=false --nodes <NODE_IP>
```

This reboots the node; with USB/ISO first in boot order it will then boot into the installer (maintenance mode), where you can apply a new configuration.

> **Note:** There is no `talosctl reboot --mode maintenance`. Use `talosctl reset --system-labels-to-wipe ... --reboot` as above, or a full `talosctl reset --reboot` if you intend to wipe the disk.

Without IPMI, persistent boot media or BMC access remains the main recovery path if the OS does not come up.

## Related docs

- [talos.md](talos.md) -- version pin, installer URL shape, `talosctl`
- [cluster-network.md](cluster-network.md) -- Cilium, Talos host DNS, VIP
- [secrets.md](secrets.md) -- talosconfig and kubeconfig
- [rising-deployment.md](rising-deployment.md) -- first bare-metal worker (Rising), prod tfvars, USB and apply flow
