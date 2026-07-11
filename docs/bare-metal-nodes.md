# Bare-Metal Talos Nodes

This document describes how **bare-metal** Talos workers fit into the Tiles Terraform layout. **Source of truth:** [tf/nodes/talos-iso.tf](../tf/nodes/talos-iso.tf), [tf/nodes/cluster.tf](../tf/nodes/cluster.tf), [tf/modules/talos-cluster/nodes.tf](../tf/modules/talos-cluster/nodes.tf), and [tf/modules/talos-metal/main.tf](../tf/modules/talos-metal/main.tf). Do not copy Image Factory schematic IDs from docs; they change whenever `talos_version` or schematic YAML changes. Use `terraform output` or the Terraform plan for current values.

Tiles pins `talos_version` in [tf/nodes/terraform.tfvars](../tf/nodes/terraform.tfvars) (for example the **1.13** release line). Outbound links to Sidero Labs docs use **v1.13** where a versioned URL exists.

## What Terraform implements

### Metal schematics (AMD vs Intel)

Bare-metal workers use one of two Image Factory schematics in [tf/nodes/talos-iso.tf](../tf/nodes/talos-iso.tf). Both use the **metal** platform variant and share kernel args `net.ifnames=0` and `-talos.halt_if_installed`. The leading `-` follows Talos kernel syntax for **dropping** a parameter: it clears `talos.halt_if_installed` so the ISO can hand off to an existing disk install after the boot timeout instead of stopping for "already installed" ([kernel reference](https://docs.siderolabs.com/talos/v1.13/reference/kernel), [issue #10090](https://github.com/siderolabs/talos/issues/10090)).

| CPU class | Tfvars map | Schematic resource | Extensions |
|-----------|------------|-------------------|------------|
| AMD (Ryzen APU, etc.) | `metal_amd_nodes` | `talos_image_factory_schematic.metal_amd` | `amd-ucode`, `amdgpu`, `amdgpu-firmware` |
| Intel (e.g. Alder Lake-N UHD) | `metal_intel_nodes` | `talos_image_factory_schematic.metal_intel` | `intel-ucode`, `i915` |

AMD extensions cover **CPU microcode and the integrated Radeon GPU** (`amd-ucode`, `amdgpu`, `amdgpu-firmware`). The separate **Ryzen AI (XDNA) inference IP** is not shipped as a Talos extension.

Intel extensions cover **CPU microcode and integrated graphics** (`intel-ucode`, `i915`). The `i915` extension supplies GPU firmware and kernel modules (see [siderolabs/extensions `drm/i915`](https://github.com/siderolabs/extensions/tree/main/drm/i915)). That matches AceBase-class **Alder Lake-N** UHD; newer Intel GPUs that use the **`xe`** driver need a different schematic (add `xe` in `talos-iso.tf`, not both `i915` and `xe` on one image).

**USB ISO outputs** (from `tf/nodes/`):

- AMD: `terraform output metal_amd_iso_url`
- Intel: `terraform output metal_intel_iso_url`

Proxmox **VMs** use **`talos_image_factory_schematic.vm`** in the same file: **nocloud** with **`qemu-guest-agent`** only. VMs do not use the physical metal extension sets; bare metal does not use the guest agent.

### From schematic to machine config

[tf/nodes/cluster.tf](../tf/nodes/cluster.tf) passes VM and metal schematic IDs from `talos-iso.tf` into **`module.cluster`**. [tf/modules/talos-cluster/nodes.tf](../tf/modules/talos-cluster/nodes.tf) turns those IDs into Image Factory **installer** URLs: VMs use `factory.talos.dev/installer/...`; metal workers use **`factory.talos.dev/metal-installer/...`** ([Image Factory](https://docs.siderolabs.com/talos/v1.13/learn-more/image-factory), [talos.md](talos.md) for VM URLs).

`module.talos-amd-metal` is keyed by `metal_amd_nodes`; `module.talos-intel-metal` by `metal_intel_nodes`. Each node gets the install patch for its schematic.

For **every** node (VM or metal), the same patch stack applies the shared [talos-config.yaml](../tf/modules/talos-cluster/talos-config.yaml), the same cluster name and pod/service CIDRs, optional kubelet taints, and control-plane-only patches (for example Layer2 VIP) **only** when `type = "control"` in tfvars. Bare-metal nodes in this layout are **workers**; the meaningful difference from a VM worker is the single install patch: **`machine.install.image`** uses **metal-installer** with the node's metal schematic instead of the VM **installer** with the VM schematic.

### Metal module behavior

[tf/modules/talos-metal/main.tf](../tf/modules/talos-metal/main.tf) does **not** create a Proxmox VM. It:

1. Registers the MAC in UniFi (fixed IP, local DNS name).
2. Runs `talos_machine_configuration_apply` against the node IP.

The host must already be running Talos (maintenance mode from the Talos metal ISO on USB, or already installed) so the Talos machine API is reachable on the node IP (default TCP **50000**). Booting from that ISO does not install to disk until machine configuration is applied; see the upstream [bare-metal ISO](https://docs.siderolabs.com/talos/v1.13/platform-specific-installations/bare-metal-platforms/iso) guide.

### When bare-metal resources run

Workspace tfvars (`test.tfvars`, `prod.tfvars`, etc.) set `metal_amd_nodes` and/or `metal_intel_nodes` per environment ([tf/nodes/variables.tf](../tf/nodes/variables.tf)). Adding a worker means adding an entry to the map that matches the host CPU and applying Terraform.

## Operations

Use the talosconfig for the right cluster ([secrets.md](secrets.md#talos-client-configuration-talosconfig)). For `talosctl reset` flags, see [Resetting a machine](https://docs.siderolabs.com/talos/v1.13/configure-your-talos-cluster/lifecycle-management/resetting-a-machine/) (Talos v1.13).

### 1. Add a bare-metal worker to the cluster

1. **Cluster must exist** -- Bootstrap comes from control plane VMs. Bare metal in this layout is **workers only**; the control plane stays on Proxmox VMs.
2. **Pick IP and MAC** -- Align with [cluster-network.md](cluster-network.md) and UniFi; the metal module creates the UniFi fixed-IP client.
3. **Add the node** in workspace tfvars: `metal_amd_nodes` for AMD (e.g. Rising -- facts repo `fables/Tiles/Rising.md`) or `metal_intel_nodes` for Intel (e.g. AceBase -- `facts/fables/kb/Computers/AceBase.md`).
4. **Prepare USB** -- From `tf/nodes/`, run `terraform plan` or `terraform apply` with the right `-var-file=...`, then read **`metal_amd_iso_url`** or **`metal_intel_iso_url`** as appropriate. Download that `metal-amd64.iso`, then write it to USB.
5. **Boot the machine** from USB into the Talos installer (in-memory maintenance mode).
6. **`terraform apply`** -- Once the Talos API answers on the node IP, `talos_machine_configuration_apply` sends the config and the node installs to disk from `machine.install.image` (`metal-installer` schematic). This resource is **fire-and-forget**: it returns as soon as the maintenance-mode node accepts the config (often `Creation complete after 0s`) and does **not** wait for the install or cluster join. A green apply means "config delivered", not "node installed" -- always confirm with step 7.
7. **Verify** -- After reboot, `kubectl get nodes` and `talosctl get members --nodes <NODE_IP>`. If the node never appears, check whether it is still in maintenance mode: `talosctl -n <NODE_IP> version --insecure` answering means it booted the ISO but did **not** install -- see [Install disk](#install-disk-machine-with-an-existing-os).

You may run `terraform apply` once before the machine is booted: UniFi objects are created first; `talos_machine_configuration_apply` fails or times out until the node is reachable. Boot from USB, then apply again.

### Install disk (machine with an existing OS)

The shared config sets no `machine.install.disk`, so Talos auto-selects one. That works on an empty or spare disk (AceBase installed onto an empty SATA SSD). It does **not** work when the node's **only** disk already holds another OS: Talos won't clobber the occupied disk, so the config is accepted but the install never runs and the node **silently stays in maintenance mode** (Lancer shipped with Windows on its sole NVMe and did exactly this). Add a per-node patch pinning the disk and wiping it -- see [tf/nodes/patches/lancer-install-disk.yaml](../tf/nodes/patches/lancer-install-disk.yaml):

```yaml
machine:
  install:
    disk: /dev/nvme0n1   # target disk; find it with: talosctl -n <IP> get disks --insecure
    wipe: true           # overwrites the existing OS
```

Wire it in via `machine_config_patches` on the node's tfvars entry. Changing `config_patches` is a real diff, so a plain `terraform apply` re-applies (no taint needed) and the install proceeds. Maintenance mode exposes only `version` / `get` / `disks` / `apply-config` over `--insecure` -- **not** `dmesg`, service `logs`, or `events` -- so watch an install attempt on console/serial, not via `talosctl`.

### 2. Remove a bare-metal worker from the cluster

Terraform only removes the **UniFi client** and the **`talos_machine_configuration_apply`** resource. It does **not** remove the node from Kubernetes or wipe the disk.

1. **Evict workloads** -- `kubectl cordon <node-name>` then `kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data` (add `--force` only if you accept deleting standalone pods). Wait until drain completes.
2. **Remove the Kubernetes node object** -- `kubectl delete node <node-name>`.
3. **Remove Terraform state** -- Delete that node's entry from `metal_amd_nodes` or `metal_intel_nodes` and run `terraform apply`.
4. **Optional: wipe the machine** -- See [Wipe and reinstall](#3-wipe-and-reinstall-talos-on-the-same-machine).

### 3. Wipe and reinstall Talos on the same machine

**A. Node still reaches the Talos API**

1. Partial wipe and reboot toward USB maintenance:

   ```bash
   talosctl --talosconfig ~/.talos/tiles.yaml reset \
     --system-labels-to-wipe EPHEMERAL --system-labels-to-wipe STATE \
     --reboot --graceful=false --nodes <NODE_IP>
   ```

2. Boot from USB using the **correct** ISO for that CPU (`metal_amd_iso_url` vs `metal_intel_iso_url`).

3. Run **`terraform apply`** again.

**B. Full disk wipe** -- `talosctl reset --reboot --graceful=false`, then USB if needed, then apply as in **Add** step 6.

## ISO and installer URL patterns

Replace placeholders from Terraform outputs or plan. Generic Talos bare-metal context: [ISO](https://docs.siderolabs.com/talos/v1.13/platform-specific-installations/bare-metal-platforms/iso), [Image Factory](https://docs.siderolabs.com/talos/v1.13/learn-more/image-factory).

- **Metal ISO:** `https://factory.talos.dev/image/<SCHEMATIC>/v<TALOS_VERSION>/metal-amd64.iso`
- **Installer image (machine config):** `factory.talos.dev/metal-installer/<SCHEMATIC>:v<TALOS_VERSION>`

`TALOS_VERSION` in URLs uses the `v` prefix (e.g. `v1.13.0`); `terraform.tfvars` uses the same string without `v` (e.g. `1.13.0`).

## Full-cluster rebuilds and VMs

The [Recreating cluster](../README.md#recreating-cluster) flow taints the Proxmox **VMs** and **`talos_machine_bootstrap`**, so Terraform builds new VM disks and **re-bootstraps etcd** -- a brand-new cluster. Bare-metal nodes are **not** VMs and are **not** recreated by that flow, which is exactly where they get stranded.

### Rebuilds: metal reapply + reboot

**The trap.** A metal worker's machine config is derived from `talos_machine_secrets`, which a bootstrap recreate does **not** change. Re-applying it therefore produces byte-identical config, and `talos_machine_configuration_apply` under `apply_mode = "auto"` is a **no-op -- no reboot** (this is exactly why `apply_mode` now **defaults to `reboot`**; see below). The node keeps its old in-memory etcd/kubelet identity, its Node object was wiped with the old etcd, and the long-running kubelet loops `nodes "<name>" not found`; `NodeRestriction` then denies every pod pinned there. (Observed 2026-06-30 -> 07-01: `acebase` -- the GNSS base -- sat orphaned ~35h, so `ntrip/rtkbase` + `mavproxy` were `Pending` and **RTK was down**. See [tiles#547](https://github.com/symmatree/tiles/issues/547).)

A config *apply* is not a *reset*. PKI is preserved across the recreate (both apid mTLS and the kubelet client cert still authenticate), so the node needs neither new certs nor a reinstall -- it only needs to **reboot** (or at minimum `talosctl -n <NODE_IP> service kubelet restart`) to rejoin. Since `auto` won't reboot on unchanged config, we force it.

**The mechanism -- two knobs, both required:**

1. **[`taint-vms`](../.github/workflows/taint-vms.yaml)** taints each metal `talos_machine_configuration_apply` (derived from state, so it tracks `metal_{amd,intel}_nodes` automatically) so the apply re-runs on the next Terraform apply.
2. **[`nodes-plan-apply`](../.github/workflows/nodes-plan-apply.yaml)** takes a **`metal_apply_mode`** input, threaded via `TF_VAR_metal_apply_mode` into the metal module's `apply_mode`. It **defaults to `reboot`**, which a rebuild requires: the re-applied node reboots and rejoins the new etcd. The metal modules `depends_on` `talos_machine_bootstrap`, so the reboot lands **after** the new etcd exists.

`metal_apply_mode` now **defaults to `reboot`** for every apply (PR / push / daily schedule / dispatch). This is **not** a reboot-every-apply: the metal `talos_machine_configuration_apply` has no `replace_triggered_by` and stable inputs, so Terraform only re-runs it -- and only reboots -- when the metal config **actually changes** (or on a `taint-vms` rebuild). Rebooting on a real change guarantees the config fully applies (Talos `auto` reboots only when it judges a changed field requires it, which is unreliable -- it can hold state until reboot) and lets a rebuilt node rejoin the new etcd. Override to `auto` / `no_reboot` / `staged` only when you deliberately want a live-only apply.

> **apply-config modes** ([Talos v1.13](https://docs.siderolabs.com/talos/v1.13/configure-your-talos-cluster/system-configuration/editing-machine-configuration)): `auto` reboots only if a changed field requires it; `no_reboot` fails if a reboot would be needed; `reboot` always reboots to apply; `staged` applies on next reboot. Changes Terraform apply cannot make at all (install disk, disk encryption, wiping state) need a **reset**, not an apply -- see [Wipe and reinstall](#3-wipe-and-reinstall-talos-on-the-same-machine).
>
> Why `reboot` works on unchanged config: in v1.13 machined's `ApplyConfiguration` REBOOT case persists the config and **unconditionally** sequences a reboot -- there is no config-diff short-circuit ([v1alpha1_server.go](https://github.com/siderolabs/talos/blob/v1.13.0/internal/app/machined/internal/server/v1alpha1/v1alpha1_server.go)). **Forward-compat:** the deprecated `REBOOT` gRPC mode is slated for removal on Talos `main` ("use AUTO or NO_REBOOT"), so **re-verify this mechanism when bumping `talos_version`** past 1.13.

**Rebuild runbook**

1. Run **`taint-vms`** for the workspace (taints VMs, `talos_machine_bootstrap`, and metal config-apply).
2. Run **`nodes-plan-apply`** with **apply** for that workspace (**`metal_apply_mode`** defaults to **`reboot`**, which the rebuild needs).
3. Verify: `talosctl -n <NODE_IP> get members` and `kubectl get nodes` show the metal node; any pinned pods (e.g. `ntrip`, `mavproxy`) return to `Running`.

## Related docs

- [talos.md](talos.md) -- version pin, installer URL shape, `talosctl`
- [cluster-network.md](cluster-network.md) -- Cilium, Talos host DNS, VIP
- [secrets.md](secrets.md) -- talosconfig and kubeconfig
