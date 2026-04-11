# Bare-Metal Talos Nodes (AMD)

This document describes how **bare-metal** Talos workers fit into the Tiles Terraform layout. **Source of truth:** [tf/nodes/talos-iso.tf](../tf/nodes/talos-iso.tf), [tf/nodes/cluster.tf](../tf/nodes/cluster.tf), [tf/modules/talos-cluster/nodes.tf](../tf/modules/talos-cluster/nodes.tf), and [tf/modules/talos-metal/main.tf](../tf/modules/talos-metal/main.tf). Do not copy Image Factory schematic IDs from docs; they change whenever `talos_version` or schematic YAML changes. Use `terraform output` or the Terraform plan for current values.

## What is already implemented

### Two Image Factory schematics

In `tf/nodes/talos-iso.tf`:

1. **`talos_image_factory_schematic.vm`** -- Proxmox / **nocloud** images with `qemu-guest-agent` and VM-oriented kernel args (`vga=792`, `net.ifnames=0`, `-talos.halt_if_installed`).
2. **`talos_image_factory_schematic.metal_amd`** -- **metal** images with `amd-ucode`, `amdgpu`, `amdgpu-firmware` and `net.ifnames=0`, `-talos.halt_if_installed`.

Terraform outputs include `vm_schematic_id`, `metal_amd_schematic_id`, and `metal_amd_iso_url`.

### Wiring into the cluster module

[tf/nodes/cluster.tf](../tf/nodes/cluster.tf) passes `talos_vm_schematic` and `talos_metal_amd_schematic` into `module.cluster`. [tf/modules/talos-cluster/nodes.tf](../tf/modules/talos-cluster/nodes.tf) sets:

- `vm_install_image` = `factory.talos.dev/installer/${vm_schematic}:v${talos_version}` for `module.talos-vm`
- `metal_amd_install_image` = `factory.talos.dev/installer/${metal_schematic}:v${talos_version}` for `module.talos-amd-metal`

Patches merge [talos-config.yaml](../tf/modules/talos-cluster/talos-config.yaml), cluster CIDRs, the correct `machine.install.image`, optional **Layer2VIPConfig** on control plane nodes only, and optional kubelet taints.

### Metal module behavior

[tf/modules/talos-metal/main.tf](../tf/modules/talos-metal/main.tf) does **not** create a Proxmox VM. It:

1. Registers the MAC in UniFi (fixed IP, local DNS name).
2. Runs `talos_machine_configuration_apply` against the node IP.

The host must already be running Talos (maintenance mode from ISO/USB/PXE, or installed) so the Talos API is reachable.

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

First-time apply from maintenance mode may use `talosctl apply-config --insecure` if certificates are not yet established; see Talos docs for your boot phase.

## Why VM and metal schematics differ

- **qemu-guest-agent** is for virtual machines only; it is not used on bare metal.
- **AMD Ryzen APU** class nodes use microcode and `amdgpu` / `amdgpu-firmware` extensions for integrated graphics firmware paths. The same extension set is documented for Phoenix-class APUs in fleet notes; adjust the extension list in `talos-iso.tf` if you add different hardware.

**NPU / Ryzen AI:** There is no separate Talos system extension for the XDNA NPU. GPU-oriented stacks (ROCm, operators) run as cluster workloads, not as Talos extensions.

**Intel bare metal:** The repo only defines **`metal_amd`** today. Intel would need a parallel schematic data source + resource (same pattern as `metal_amd`) and a new module or `for_each` branch if you add it.

## ISO, installer, and PXE URL patterns

Replace placeholders from Terraform outputs or plan:

- **Metal ISO:** `https://factory.talos.dev/image/<METAL_AMD_SCHEMATIC>/v<TALOS_VERSION>/metal-amd64.iso`
- **Installer image (machine config):** `factory.talos.dev/installer/<METAL_AMD_SCHEMATIC>:v<TALOS_VERSION>`
- **PXE (example):** `https://pxe.factory.talos.dev/pxe/<METAL_AMD_SCHEMATIC>/v<TALOS_VERSION>/metal-amd64`

`TALOS_VERSION` in URLs uses the `v` prefix (e.g. `v1.13.0-beta.1`); `terraform.tfvars` uses the same string without `v` (e.g. `1.13.0-beta.1`).

## Kernel arg: `-talos.halt_if_installed`

Schematics set `-talos.halt_if_installed` so boot media can act as installer and recovery: the installer can hand off to an existing disk install unless you interrupt during the timeout. See Talos release notes for exact behavior on your version.

## Operational commands

Use the talosconfig for the right cluster ([secrets.md](secrets.md#talos-client-configuration-talosconfig)):

```bash
talosctl --talosconfig ~/.talos/tiles.yaml reset --reboot --graceful=false --nodes <NODE_IP>
```

- **`reset`:** Wipes disk and reboots; often used before reinstall.
- **`reboot --mode maintenance`:** Reboot into maintenance mode for reinstall without immediate wipe.

**Graceful vs not:** `--graceful=false` skips draining workloads (faster, more disruptive).

## Coordinating with VM lifecycle

If you destroy Proxmox VMs in Terraform while touching bare metal, run order and downtime matter. See [README.md](../README.md#recreating-cluster) for VM destroy targets. Bare metal resets often take longer to boot than VMs; plan accordingly.

**Optional automation:** You can wrap `talosctl reset` in `null_resource` + `local-exec`, but that hides failures in Terraform state and can surprise you on every apply if triggers are too broad. Manual or scripted steps outside Terraform are easier to reason about for rare cluster rebuilds.

## Remote management and USB / PXE

The previous long-form guidance still applies in principle:

- **USB ISO:** Write the metal ISO from the URL above; set boot order appropriately.
- **PXE:** Serve kernel/initramfs or iPXE script from Image Factory URLs with the current schematic and version.

Without IPMI, persistent boot media or BMC access remains the main recovery path if the OS does not come up.

## Related docs

- [talos.md](talos.md) -- version pin, installer URL shape, `talosctl`
- [cluster-network.md](cluster-network.md) -- Cilium, Talos host DNS, VIP
- [secrets.md](secrets.md) -- talosconfig and kubeconfig
