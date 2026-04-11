# Bare-Metal Talos Nodes (AMD)

This document describes how **bare-metal** Talos workers fit into the Tiles Terraform layout. **Source of truth:** [tf/nodes/talos-iso.tf](../tf/nodes/talos-iso.tf), [tf/nodes/cluster.tf](../tf/nodes/cluster.tf), [tf/modules/talos-cluster/nodes.tf](../tf/modules/talos-cluster/nodes.tf), and [tf/modules/talos-metal/main.tf](../tf/modules/talos-metal/main.tf). Do not copy Image Factory schematic IDs from docs; they change whenever `talos_version` or schematic YAML changes. Use `terraform output` or the Terraform plan for current values.

Tiles pins `talos_version` in [tf/nodes/terraform.tfvars](../tf/nodes/terraform.tfvars) (for example the **1.13** release line). Outbound links to Sidero Labs docs use **v1.13** where a versioned URL exists.

## What Terraform implements

### Metal AMD schematic and extensions

Bare-metal AMD workers use **`talos_image_factory_schematic.metal_amd`** in [tf/nodes/talos-iso.tf](../tf/nodes/talos-iso.tf): Image Factory **metal** images with system extensions **`amd-ucode`**, **`amdgpu`**, and **`amdgpu-firmware`** (see [system extensions](https://docs.siderolabs.com/talos/v1.13/build-and-extend-talos/custom-images-and-development/system-extensions)), plus kernel args `net.ifnames=0` and `-talos.halt_if_installed`. The leading `-` follows Talos kernel syntax for **dropping** a parameter: it clears `talos.halt_if_installed` so the ISO can hand off to an existing disk install after the boot timeout instead of stopping for "already installed" ([kernel reference](https://docs.siderolabs.com/talos/v1.13/reference/kernel), [issue #10090](https://github.com/siderolabs/talos/issues/10090)).

Those extensions cover **CPU microcode and the integrated Radeon GPU** on typical Ryzen APU boxes. The separate **Ryzen AI (XDNA) inference IP** is not shipped as a Talos extension; anything you do with it later is ordinary Linux/Kubernetes software, not part of this schematic. Change the extension list in `talos-iso.tf` if you target different AMD hardware.

Proxmox **VMs** use **`talos_image_factory_schematic.vm`** in the same file: **nocloud** with **`qemu-guest-agent`** only (no AMD firmware or GPU extensions). VMs do not need the physical AMD extension set; bare metal does not use the guest agent.

### From schematic to machine config

[tf/nodes/cluster.tf](../tf/nodes/cluster.tf) passes the VM and metal schematic IDs from `talos-iso.tf` into **`module.cluster`**. [tf/modules/talos-cluster/nodes.tf](../tf/modules/talos-cluster/nodes.tf) turns those IDs into Image Factory **installer** URLs: VMs use `factory.talos.dev/installer/...`; metal workers use **`factory.talos.dev/metal-installer/...`** ([Image Factory](https://docs.siderolabs.com/talos/v1.13/learn-more/image-factory), [talos.md](talos.md) for VM URLs).

For **every** node (VM or metal), the same patch stack applies the shared [talos-config.yaml](../tf/modules/talos-cluster/talos-config.yaml), the same cluster name and pod/service CIDRs, optional kubelet taints, and control-plane-only patches (for example Layer2 VIP) **only** when `type = "control"` in tfvars. Bare-metal nodes in this layout are **workers**; the meaningful difference from a VM worker is the single install patch: **`machine.install.image`** uses **metal-installer** with the metal schematic instead of the VM **installer** with the VM schematic.

The **metal boot ISO** download URL for this repo is Terraform output **`metal_amd_iso_url`** from `tf/nodes/` (defined next to the schematic in `talos-iso.tf`).

### Metal module behavior

[tf/modules/talos-metal/main.tf](../tf/modules/talos-metal/main.tf) does **not** create a Proxmox VM. It:

1. Registers the MAC in UniFi (fixed IP, local DNS name).
2. Runs `talos_machine_configuration_apply` against the node IP.

The host must already be running Talos (maintenance mode from the Talos metal ISO on USB, or already installed) so the Talos machine API is reachable on the node IP (default TCP **50000**). Booting from that ISO does not install to disk until machine configuration is applied; see the upstream [bare-metal ISO](https://docs.siderolabs.com/talos/v1.13/platform-specific-installations/bare-metal-platforms/iso) guide.

### When bare-metal resources run

`module.talos-amd-metal` is keyed by `metal_amd_nodes` ([tf/nodes/variables.tf](../tf/nodes/variables.tf)). Workspace tfvars (`test.tfvars`, `prod.tfvars`, etc.) set `metal_amd_nodes` per environment. Adding a worker means adding an entry to that map and applying Terraform.

## Operations

Use the talosconfig for the right cluster ([secrets.md](secrets.md#talos-client-configuration-talosconfig)). For `talosctl reset` flags, see [Resetting a machine](https://docs.siderolabs.com/talos/v1.13/configure-your-talos-cluster/lifecycle-management/resetting-a-machine/) (Talos v1.13).

### 1. Add a bare-metal AMD worker to the cluster

1. **Cluster must exist** -- Bootstrap comes from control plane VMs. Bare metal in this layout is **workers only**; the control plane stays on Proxmox VMs.
2. **Pick IP and MAC** -- Align with [cluster-network.md](cluster-network.md) and UniFi; the metal module creates the UniFi fixed-IP client.
3. **Add `metal_amd_nodes`** in the workspace tfvars for that environment. Prod has a **commented example for Rising** in [tf/nodes/prod.tfvars](../tf/nodes/prod.tfvars); uncomment it (and remove the empty `metal_amd_nodes = {}` assignment) when you are ready. Field shape is in [tf/nodes/variables.tf](../tf/nodes/variables.tf) (`metal_amd_nodes`). For Rising, MAC and BIOS context live in the facts repo `fables/Tiles/Rising.md`.
4. **Prepare USB** -- From `tf/nodes/`, run `terraform plan` or `terraform apply` with the right `-var-file=...`, then read Terraform output **`metal_amd_iso_url`**. It is a normal HTTPS URL for the metal `metal-amd64.iso` that matches this repo's schematic and pinned `talos_version`. Download that file, then write that ISO to a USB key using whatever you already use on your machine.
5. **Boot the machine** from USB into the Talos installer (in-memory maintenance mode).
6. **`terraform apply`** from `tf/nodes/` with the right `-var-file=...` -- Once the Talos API answers on the node IP, `talos_machine_configuration_apply` runs and the node installs to disk from `machine.install.image` (`metal-installer` schematic).
7. **Verify** -- After reboot, `kubectl get nodes` and/or `talosctl get members --nodes <NODE_IP>`. If you apply machine config with `talosctl` by hand (not Terraform), use `apply-config --insecure` until node trust is established. See the Talos [getting started](https://docs.siderolabs.com/talos/v1.13/getting-started/getting-started) flow for background.

You may run `terraform apply` once before the machine is booted: UniFi objects are created first; `talos_machine_configuration_apply` fails or times out until the node is reachable. Boot from USB, then apply again.

### 2. Remove a bare-metal worker from the cluster

Terraform only removes the **UniFi client** and the **`talos_machine_configuration_apply`** resource. It does **not** remove the node from Kubernetes or wipe the disk.

1. **Evict workloads** -- `kubectl cordon <node-name>` then `kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data` (add `--force` only if you accept deleting standalone pods). Wait until drain completes.
2. **Remove the Kubernetes node object** -- `kubectl delete node <node-name>` so the control plane forgets this member.
3. **Remove Terraform state for the machine** -- Delete that node's entry from `metal_amd_nodes` in the workspace tfvars and run `terraform apply`. That drops the UniFi reservation and the apply resource.
4. **Optional: wipe the machine** -- If you will reuse or dispose of the hardware, run `talosctl reset --reboot --graceful=false --nodes <NODE_IP>` while the node still answers on the API, or use physical boot media after power cycle. See [Wipe and reinstall](#3-wipe-and-reinstall-talos-on-the-same-machine).

If you skip drain/delete and only remove the tfvars entry, the OS keeps running and etcd/Kubernetes may still believe the node exists until you clean it up manually.

### 3. Wipe and reinstall Talos on the same machine

**Goal:** Talos maintenance from ISO (or full disk wipe), then re-join the same cluster with a fresh install.

**A. Node still reaches the Talos API (normal case)**

1. Clear installed state but keep planning to boot from USB for the next boot:

   ```bash
   talosctl --talosconfig ~/.talos/tiles.yaml reset \
     --system-labels-to-wipe EPHEMERAL --system-labels-to-wipe STATE \
     --reboot --graceful=false --nodes <NODE_IP>
   ```

2. Ensure **USB with the current metal ISO** is first in boot order (Rising BIOS notes: facts repo `fables/Tiles/Rising.md`). After reboot the machine should be in installer/maintenance mode from RAM.

3. Run **`terraform apply`** again so `talos_machine_configuration_apply` pushes machine config and the installer writes to disk.

**B. Full disk wipe before install**

Use when you want every partition gone (an aggressive reinstall):

```bash
talosctl --talosconfig ~/.talos/tiles.yaml reset --reboot --graceful=false --nodes <NODE_IP>
```

Then boot from USB if the node no longer has a bootable OS, and apply Terraform as in **Add** step 6.

**Graceful vs not:** `--graceful=false` skips cordon/drain inside Talos; use it for nodes you have already drained in Kubernetes or for broken workers.

## ISO and installer URL patterns

Replace placeholders from Terraform outputs or plan. Generic Talos bare-metal context: [ISO](https://docs.siderolabs.com/talos/v1.13/platform-specific-installations/bare-metal-platforms/iso), [Image Factory](https://docs.siderolabs.com/talos/v1.13/learn-more/image-factory).

- **Metal ISO:** `https://factory.talos.dev/image/<METAL_AMD_SCHEMATIC>/v<TALOS_VERSION>/metal-amd64.iso`
- **Installer image (machine config, bare metal):** `factory.talos.dev/metal-installer/<METAL_AMD_SCHEMATIC>:v<TALOS_VERSION>`

`TALOS_VERSION` in URLs uses the `v` prefix (e.g. `v1.13.0-beta.1`); `terraform.tfvars` uses the same string without `v` (e.g. `1.13.0-beta.1`).

## Full-cluster rebuilds and VMs

If you are destroying and recreating **Proxmox VMs** with Terraform at the same time as bare metal, see [README.md -- Recreating cluster](../README.md#recreating-cluster) for which VM resources to target. Bare-metal nodes are **not** destroyed by that flow; reset or reinstall them using [Wipe and reinstall](#3-wipe-and-reinstall-talos-on-the-same-machine) and expect longer reboots than VMs.

## Related docs

- [talos.md](talos.md) -- version pin, installer URL shape, `talosctl`
- [cluster-network.md](cluster-network.md) -- Cilium, Talos host DNS, VIP
- [secrets.md](secrets.md) -- talosconfig and kubeconfig
