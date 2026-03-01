# Deploying Rising (Bare-Metal AMD) into the Tiles Cluster

This document is a step-by-step plan to deploy the GMKtec NucBox K4 (hostname **Rising**) as a bare-metal Talos Linux worker in the tiles Kubernetes cluster. Rising currently has Windows installed; the goal is to install Talos with AMD firmware and driver support (for ROCm when needed), then apply the same machine-config flow used for Proxmox VMs [1].

**Status:** No bare-metal node has been added to the tiles cluster yet. This deployment will be the first test of the bare-metal doc, Terraform wiring (metal-installer image, talos-metal module), and this guide. Expect to adjust steps or docs if something does not match your environment.

Hardware summary: AMD Ryzen 9 7940HS, Radeon 780M iGPU, 32 GB DDR5, 1 TB NVMe. Network and BIOS details are in the facts repo [2].

---

## 1. Talos settings for the node (AMD + ROCm-ready)

The right Talos Linux image for this node is already defined in Terraform [3]:

- **Schematic** (bare-metal AMD): `tf/nodes/talos-iso.tf` defines `talos_image_factory_schematic.metal_amd` with:
  - **Extensions:** `amd-ucode`, `amdgpu`, `amdgpu-firmware` [4][5]
  - **Kernel args:** `net.ifnames=0`, `-talos.halt_if_installed` [6]

No code changes are required for Talos settings. The same schematic is used for any bare-metal AMD Ryzen APU (e.g. 7940HS, Ryzen AI Max+ 395) [4]. Optional kernel tuning (e.g. `amdgpu.gttsize`, `ttm.pages_limit`) is only needed for some newer/high-memory GPUs [7]; 780M can be tried without it first.

**ROCm:** Talos extensions provide the kernel driver and firmware; exposing the GPU to Kubernetes is done later by deploying the ROCm GPU Operator in the cluster [7][8]. The NPU (XDNA) has no Talos extension because it is not a kernel-mode driver. NPU support on Linux (and whether/how it can be used from Kubernetes) is unclear and would need investigation; the doc does not assume there is a known install path or “Ryzen AI in Kubernetes” option today.

---

## 2. Add Rising to Terraform (prod)

Add Rising to `metal_amd_nodes` in **prod** so Terraform creates the Unifi client (fixed IP) and the `talos_machine_configuration_apply` resource [1][9].

**File:** `tf/nodes/prod.tfvars`

Replace:

```hcl
metal_amd_nodes = {}
```

with:

```hcl
metal_amd_nodes = {
  "rising" = {
    name        = "rising"
    type        = "worker"
    mac_address = "84:47:09:2f:a9:ef"
    ip_address  = "10.0.128.52"
    taint       = "rising"
  }
}
```

Data source: [2]. Taint `rising` allows scheduling only workloads that tolerate it; change to `""` if you want general workloads. Optional: use a taint like `amd-gpu` if you plan to target GPU nodes by label/taint.

After editing, run from `tf/nodes/`:

```bash
terraform plan -var-file=prod.tfvars
```

You can run `terraform apply` once before Rising is booted: Terraform will create the Unifi client (fixed IP for Rising’s MAC) so that when the node boots from USB it gets 10.0.128.52. The `talos_machine_configuration_apply` step will fail or timeout until the node is reachable. Boot Rising from USB into maintenance mode, then run `terraform apply` again; the machine config will then apply and the installer will write Talos to disk [1].

---

## 3. Get the Talos image onto a memory stick

- **ISO URL** (from Terraform): after `terraform plan` or `terraform apply`, use the output:
  - `metal_amd_iso_url` from the nodes module, or
  - Direct form: `https://factory.talos.dev/image/<metal_amd_schematic_id>/v<talos_version>/metal-amd64.iso` [3][10].

- **Write ISO to USB** (Linux; replace `sdX` with the USB device, e.g. `sdb`):

  ```bash
  # Identify device: lsblk
  dd if=talos-metal-amd64.iso of=/dev/sdX bs=4M status=progress
  ```

- **Download the ISO:** either use the URL from Terraform output, or from the Image Factory with the schematic ID [10].

References: [1] (USB stick with ISO), [3] (output `metal_amd_iso_url`).

---

## 4. Configure BIOS and boot order

On Rising (GMKtec NucBox K4), enter BIOS by pressing `Esc` repeatedly [2].

- **Boot:** Set USB as first boot device so the Talos installer (ISO) boots from the memory stick.
- **UMA frame buffer:** Leave as **Auto** (recommended for video/GPU workloads) [2][11].
- **Secure Boot:** Disabled (per [2]).
- **UEFI Network:** Can stay disabled; we use local USB boot [2].

No other BIOS changes are required for Talos. Full BIOS notes: [2].

---

## 5. Boot from USB and apply machine config

1. **Unifi reservation:** If you already ran `terraform apply` once (step 2), the Unifi client for MAC `84:47:09:2f:a9:ef` with IP `10.0.128.52` exists. If not, run apply once so the node gets that IP when it boots.

2. **Boot Rising:** Insert the USB stick, power on. The node should boot into the Talos installer (runs in memory). It will receive `10.0.128.52` via DHCP from Unifi [1].

3. **Apply Terraform:** From `tf/nodes/`:
   ```bash
   terraform apply -var-file=prod.tfvars
   ```
   This runs `talos_machine_configuration_apply` for Rising: it applies the worker machine config (with bare-metal installer image `factory.talos.dev/metal-installer/...` [3][10]) to the node at 10.0.128.52. The installer will write Talos to disk and the node will reboot into the cluster.

4. **Verify:** After reboot, the node should join the cluster. Use `kubectl get nodes` (with kubeconfig from 1Password [12]) and/or `talosctl --talosconfig ~/.talos/tiles.yaml get members --nodes 10.0.128.52`.

**If apply fails** (e.g. node not reachable): ensure Rising is on the same network, has booted from USB into the Talos installer, and that no firewall blocks Talos API (port 50000). Then re-run `terraform apply`.

References: [1] (apply-config flow, `talosctl apply-config` equivalent via Terraform), [9] (talos-metal module).

---

## 6. Red flags and things to consider

- **First apply before boot:** Running `terraform apply` before Rising is in maintenance mode creates the Unifi client but `talos_machine_configuration_apply` will fail or timeout. Boot Rising from USB, then run apply again (see step 2 and step 5).

- **Bootstrap:** Cluster bootstrap (and kubeconfig) depend only on the Proxmox VMs, not on metal nodes [13]. Adding Rising does not block bootstrap.

- **misc_config worker_ips:** The 1Password item `tiles-misc-config` field `worker_ips` is built only from VM workers, not metal workers [13]. If any automation relies on that list, consider extending it to include metal worker IPs (e.g. 10.0.128.52).

- **ROCm / 780M:** The Radeon 780M is an iGPU; ROCm support for iGPUs can be less complete than for discrete GPUs. If ROCm workloads fail, check Talos AMD GPU docs and ROCm GPU Operator logs [7][8]. Optional kernel args (e.g. for large buffers) are in [7].

- **Disk:** Installing Talos wipes the existing Windows installation on the NVMe.

- **Remote recovery:** Keeping the USB in the machine and setting boot order to prefer USB allows remote recovery: power-cycle the node so it boots from USB into maintenance mode, then re-apply config. To return to maintenance mode without physical access (when the node is still reachable), use `talosctl reset --system-labels-to-wipe EPHEMERAL --system-labels-to-wipe STATE --reboot --graceful=false` then let it boot from USB [1].

- **IPU/NPU:** The AMD XDNA IPU is not managed by Talos extensions; NPU support on Linux/Kubernetes is unclear (see section 1) [4].

---

## 7. Optional follow-up

- **ROCm in Kubernetes:** Deploy the ROCm GPU Operator to expose the GPU to pods [7][8]:
  ```bash
  helm repo add rocm https://rocm.github.io/gpu-operator
  helm install rocm-gpu-operator rocm/gpu-operator -n kube-system
  ```
- **Facts:** Update [2] after deployment (e.g. note Talos installed, date, taint).
- **Docs index:** This file is linked from [14].

---

## Appendix: Sources and references

Use these links to re-validate steps or to let a future agent re-fetch the same sources.

[1] **Bare-metal nodes (tiles)**  
`docs/bare-metal-nodes.md` in this repo. Covers: schematic vs VM, firmware extensions, AMD Ryzen APU config, USB vs PXE, `talosctl apply-config` and reset (use `reset --system-labels-to-wipe EPHEMERAL,STATE --reboot` to return to maintenance mode; there is no `reboot --mode maintenance`), Terraform integration, machine config generation, remote recovery. Includes a **Verification notes** section at the end with sources and corrections (e.g. metal-installer URL).

[2] **Rising hardware and BIOS (facts)**  
`facts/Tiles/Rising.md` (path relative to facts repo). Contains: component summary, BIOS version and options (UMA, Secure Boot, boot config), network info (IP 10.0.128.52, MAC 84:47:09:2f:a9:ef), UniFi references.

[3] **Talos ISO and metal AMD schematic (tiles)**  
`tf/nodes/talos-iso.tf`. Defines `talos_image_factory_schematic.metal_amd` (amd-ucode, amdgpu, amdgpu-firmware), `metal_amd_iso_url` output, and VM schematic.  
`tf/nodes/cluster.tf` passes `talos_metal_amd_schematic` into the cluster module.

[4] **Bare-metal AMD extensions and ROCm/NPU (tiles)**  
`docs/bare-metal-nodes.md` sections “Adding Firmware Extensions”, “AMD Ryzen APU Configuration”, “Ryzen AI Engine / NPU Support”. Official extension names and note that NPU is not a Talos extension.

[5] **Talos system extensions (official)**  
https://docs.siderolabs.com/talos/latest/talos-guides/configuration/system-extensions/  
(System extensions overview; extension list and naming.)

[6] **halt_if_installed (tiles)**  
`docs/bare-metal-nodes.md` note under “Example Bare-Metal Schematic Configuration”. Explains `-talos.halt_if_installed` for USB-as-fallback boot.

[7] **Talos AMD GPU and ROCm (official)**  
https://docs.siderolabs.com/talos/latest/configure-your-talos-cluster/hardware-and-drivers/amd-gpu  
Covers: amd-ucode + amdgpu (and optional firmware), optional kernel args for tuning, deploying the ROCm GPU Operator, troubleshooting.

[8] **ROCm GPU Operator (Helm)**  
https://rocm.github.io/gpu-operator  
Helm repo and install for exposing AMD GPUs to Kubernetes after Talos has loaded the driver.

[9] **Talos-metal Terraform module (tiles)**  
`tf/modules/talos-metal/main.tf`. Creates `unifi_user` (fixed IP + local DNS) and `talos_machine_configuration_apply` for a bare-metal node.  
`tf/modules/talos-cluster/nodes.tf` calls `module "talos-amd-metal"` with `metal_amd_install_image` (using `factory.talos.dev/metal-installer/...`) and patches.

[10] **Talos Image Factory**
https://factory.talos.dev/
Build custom images (ISO, installer, PXE) from a schematic. ISO URL pattern: `https://factory.talos.dev/image/<schematic-id>/v<version>/metal-amd64.iso`. For bare-metal, the installer image (used in machine.install.image) is `factory.talos.dev/metal-installer/<schematic-id>:v<version>` (see bare-metal-nodes.md verification notes).

[11] **AMD UMA frame buffer**  
https://www.amd.com/en/resources/support-articles/faqs/PA-280.html  
Recommends “Auto” for UMA frame buffer for most video processing workloads.

[12] **Dev setup and kubeconfig (tiles)**  
`docs/dev-setup.md`. How to get kubeconfig and talosconfig from 1Password for the tiles cluster.

[13] **Bootstrap and misc_config (tiles)**  
`tf/modules/talos-cluster/main.tf`: `talos_machine_bootstrap` and `talos_cluster_kubeconfig` depend on `module.talos-vm` only; `onepassword_item.misc_config` builds `worker_ips` from `var.vms` only.

[14] **Documentation index (tiles)**  
`docs/index.md`. Lists all docs; add or keep an entry for “Rising deployment” pointing to this file.

---

*All links use ASCII double quotes. Paths are relative to the tiles repo root unless stated (e.g. “facts repo”).*
