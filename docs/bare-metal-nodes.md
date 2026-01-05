# Bare-Metal Talos Nodes

This document outlines the process for adding bare-metal nodes to the Talos cluster. These nodes will run Talos directly on physical hardware (not under Proxmox) and will be configured as single worker nodes to maximize the size of jobs they can allocate.

## Computing Different Install Manifests for Bare-Metal Nodes

Bare-metal nodes require different Talos installation manifests compared to Proxmox VMs. The key differences are:

### Removing QEMU Guest Agent

Proxmox VMs use the `qemu-guest-agent` extension, which is not needed (and not available) on bare-metal hardware. The current cluster uses schematic `ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515` which includes:

```yaml
customization:
  systemExtensions:
    officialExtensions:
      - siderolabs/qemu-guest-agent
```

For bare-metal nodes, create a new schematic without this extension using Terraform. The existing `tf/nodes/talos-iso.tf` creates a schematic for Proxmox VMs. You'll need to create a separate schematic resource for bare-metal nodes.

**Terraform Approach:**

- Create a new schematic resource in Terraform (similar to `talos_image_factory_schematic.this` in `tf/nodes/talos-iso.tf`)
- Use a variable to specify bare-metal extensions (excluding `qemu-guest-agent`, including firmware extensions)
- The schematic will be generated via the `talos_image_factory_schematic` resource
- Use the schematic ID to construct installer image URLs and ISO download URLs

### Adding Firmware Extensions

Bare-metal nodes may require firmware extensions for their processors and hardware:

- **Intel processors:** `siderolabs/intel-ucode` - Intel microcode updates
- **AMD processors:** `siderolabs/amd-ucode` - AMD microcode updates
- **AMD GPU support:** `siderolabs/amdgpu` - AMD GPU driver (for integrated Radeon graphics)
- **AMD GPU firmware:** `siderolabs/amdgpu-firmware` - AMD GPU firmware (required for GPU functionality)
- **NVIDIA GPU:** `siderolabs/nvidia` - NVIDIA GPU support
- **Network drivers:** Most modern network cards are supported, but check if specific drivers are needed

### AMD Ryzen APU Configuration

For AMD Ryzen APUs with integrated graphics (including Ryzen 9 7940HS and Ryzen AI Max+ 395), use the following extensions:

```hcl
variable "talos_bare_metal_extensions" {
  description = "Talos extensions for bare-metal AMD Ryzen nodes"
  type        = list(string)
  default     = [
    "amd-ucode",        # CPU microcode updates
    "amdgpu",           # AMD GPU driver for integrated Radeon graphics
    "amdgpu-firmware"   # AMD GPU firmware (required for GPU to function)
  ]
}
```

**This same set of extensions works for:**

- **AMD Ryzen 9 7940HS** - Phoenix architecture, RDNA 3 graphics
- **AMD Ryzen AI Max+ 395** (Strix Halo) - Zen 5 architecture, RDNA 3.5 graphics, XDNA 2 NPU

**Ryzen AI Engine / NPU Support:**

Both processors include integrated AI engines (NPU), but there is **no specific Talos system extension** for the NPU. Support is provided at the application level through:

- **AMD ROCm platform** - For GPU-accelerated AI workloads (works with the integrated Radeon graphics)
- **AMD Ryzen AI Software** - For NPU-specific workloads (deployed as Kubernetes applications, not Talos extensions)
- **ROCm GPU Operator** - Deploy in Kubernetes to expose GPU resources to workloads

The `amdgpu` and `amdgpu-firmware` extensions enable the GPU portion, which can be used for AI workloads via ROCm. The NPU portion (XDNA 1 in 7940HS, XDNA 2 in Max+ 395) requires AMD's Ryzen AI software stack to be deployed in Kubernetes, not as a Talos extension.

### Example Bare-Metal Schematic Configuration

Create a Terraform resource similar to the existing one in `tf/nodes/talos-iso.tf`. For an **AMD Ryzen 9 7940HS**, the configuration would be:

```hcl
variable "talos_bare_metal_extensions" {
  description = "Talos extensions for bare-metal nodes (no qemu-guest-agent)"
  type        = list(string)
  default     = [
    "amd-ucode",        # CPU microcode updates
    "amdgpu",           # AMD GPU driver
    "amdgpu-firmware"   # AMD GPU firmware
  ]
}

data "talos_image_factory_extensions_versions" "bare_metal" {
  talos_version = "v${var.talos_version}"
  filters = {
    names = var.talos_bare_metal_extensions
  }
}

resource "talos_image_factory_schematic" "bare_metal" {
  schematic = yamlencode(
    {
      customization = {
        systemExtensions = {
          officialExtensions = data.talos_image_factory_extensions_versions.bare_metal.extensions_info.*.name
        }
        extraKernelArgs = var.talos_schematic_extra_kernel_args
      }
    }
  )
}
```

**For Intel-based nodes**, use `["intel-ucode"]` instead. The key difference from Proxmox VMs is the absence of `qemu-guest-agent`.

Note: The `-talos.halt_if_installed` kernel argument (in `talos_schematic_extra_kernel_args`) is necessary for allowing the system to persistently boot off an ISO/USB. Without this flag, the installer will halt if it detects that Talos is already installed. With this flag, the installer will check for an installed OS and hand off to it (booting from disk) if found, unless you interrupt by hitting a key during the timeout. This enables the USB stick to serve as both an installer and a fallback recovery option while still allowing normal boot from the installed OS.

### Generating Install Manifests

The install manifests (machine configuration YAML files) are generated using `talosctl gen config` with the appropriate patches. For bare-metal nodes:

1. Use the same base configuration from `tf/modules/talos-cluster/talos-config.yaml`
2. Apply the same cluster configuration patches (cluster name, CIDRs, etc.) - but **not** the `common-patch.yaml.tmpl` which includes the installer image
3. **Use a separate patch for bare-metal installer image** that references the bare-metal schematic:
   - Format: `factory.talos.dev/installer/{schematic-id}:v{version}`
   - Example: `factory.talos.dev/installer/${talos_image_factory_schematic.bare_metal.id}:v${var.talos_version}`

**Implementation Options:**

- **Option 1: Separate patch file** - Create `bare-metal-patch.yaml.tmpl` with cluster config + bare-metal installer image, use instead of `common-patch.yaml.tmpl` for bare-metal nodes
- **Option 2: Conditional variable** - Modify `common-patch.yaml.tmpl` to use a variable like `${talos_install_image}` that's set differently for VMs vs bare-metal nodes
- **Option 3: Additional patch** - Keep `common-patch.yaml.tmpl` for cluster config, add a separate `bare-metal-installer-patch.yaml.tmpl` that only sets the installer image (patches are merged, so this overrides the installer image from common-patch)

The installer image is specified in the machine configuration's `machine.install.image` field.

## Forcing Bare-Metal Machines to Reset and Reinstall

When recreating the cluster from scratch (e.g., when tainting VMs in Terraform), you need to reset bare-metal nodes and force them into maintenance mode for reinstallation.

### Option 1: Using `talosctl reset` (Recommended)

If the node is still accessible via `talosctl`, you can reset it:

```bash
talosctl reset --reboot --graceful=false
```

This will:

- Wipe the node's disk
- Reboot the node
- Boot into maintenance mode (if booting from ISO/USB)

**Graceful vs Non-Graceful:**

- `--graceful=false` forces immediate reset without waiting for workloads to drain (faster, but may cause disruption)
- `--graceful=true` (default) waits for Kubernetes to drain the node first (slower, but safer)

### Option 2: Reboot into Maintenance Mode

If the node is running but you want to reinstall without wiping first:

```bash
talosctl reboot --mode maintenance
```

This reboots the node into maintenance mode, where you can then apply a new configuration.

### Option 3: Physical Reset (Fallback)

If the node is unresponsive or you need to force a complete reset:

1. **Power cycle the machine** (unplug/replug or use IPMI if available)
2. **Boot from USB/ISO** - Ensure boot order prioritizes USB/ISO
3. **Interrupt the boot sequence** - Because `-talos.halt_if_installed` is set, the installer will detect the installed OS and hand off to it automatically. You must interrupt the boot sequence (press a key during the timeout) using:
   - Physical keyboard (if you have physical access)
   - KVM/IPMI console (if available)
   - Or use `talosctl reboot --mode maintenance` before power cycling (if node is still accessible)

Without interrupting, the node will boot into the installed OS rather than maintenance mode.

### Integration with Terraform VM Tainting

To coordinate bare-metal node resets with Terraform VM tainting:

1. **Create a script** that:
   - Taints the VMs in Terraform: `terraform taint module.talos-cluster.module.talos-vm["vm-name"]`
   - Resets bare-metal nodes: `talosctl reset --reboot --graceful=false --nodes <bare-metal-ip>`
   - Waits for nodes to come back up in maintenance mode
   - Applies new configurations

2. **Or use Terraform null resources** to trigger the reset:

   ```hcl
   resource "null_resource" "reset_bare_metal" {
     triggers = {
       cluster_recreate = timestamp()
     }

     provisioner "local-exec" {
       command = "talosctl reset --reboot --graceful=false --nodes ${var.bare_metal_node_ip}"
     }
   }
   ```

3. **Timing considerations:**
   - Reset bare-metal nodes first (they take longer to reboot)
   - Then taint VMs in Terraform
   - Both will be ready for reconfiguration at roughly the same time

## Booting Options: Netboot vs Local USB/ISO

### Option 1: Netboot from NAS (PXE)

**Advantages:**

- Centralized management - update boot image once on NAS
- No need to physically access machines to update boot media
- Can serve different images to different machines via MAC address matching

**Requirements:**

- PXE server setup on NAS or network
- TFTP server for boot files
- HTTP server for Talos kernel/initramfs
- DHCP server configured to provide PXE boot options

**Setup:**

1. Use Terraform-generated schematic ID to construct PXE boot URLs:
   - PXE script URL: `https://pxe.factory.talos.dev/pxe/${talos_image_factory_schematic.bare_metal.id}/v${var.talos_version}/metal-amd64`
   - Or download kernel/initramfs directly from Image Factory using the schematic ID

2. Configure PXE server to serve:
   - Talos kernel (`vmlinuz`)
   - Talos initramfs (`initramfs.xz`)
   - iPXE script with kernel parameters

3. Configure DHCP to point to PXE server

4. Set bare-metal nodes to boot from network (PXE)

**Talos Installer Image Location:**

- The installer image URL is constructed from the Terraform-generated schematic: `factory.talos.dev/installer/${talos_image_factory_schematic.bare_metal.id}:v${var.talos_version}`
- This is specified in the machine configuration's `machine.install.image` field
- The installer image can be hosted on the NAS and referenced in machine config for faster installs
- Or downloaded from Image Factory during installation (default behavior)

### Option 2: Local USB Stick with ISO

**Advantages:**

- Simpler setup - no PXE server required
- Works even if network boot fails
- Can keep USB stick installed for emergency recovery

**Requirements:**

- USB stick with Talos ISO written to it
- BIOS configured to boot from USB (preferably first in boot order)

**Setup:**

1. Use Terraform to generate the ISO URL from the schematic:
   - URL: `https://factory.talos.dev/image/${talos_image_factory_schematic.bare_metal.id}/v${var.talos_version}/metal-amd64.iso`
   - You can download this via Terraform or manually using the schematic ID output

2. Write ISO to USB stick:

   ```bash
   dd if=talos-metal-amd64.iso of=/dev/sdX bs=4M status=progress
   ```

   Replace `/dev/sdX` with your USB device (use `lsblk` to identify)

3. Insert USB stick into bare-metal node

4. Configure BIOS to boot from USB first

**Talos Installer Image:**

- When booting from ISO, Talos runs in memory
- You can install a **different Talos image** to disk than the one on the ISO
- This is done by specifying `machine.install.image` in the machine configuration
- The installer image is downloaded during installation (or can be pre-hosted on NAS)

**Confirming ISO Can Install Different Image:**
Yes, this is confirmed functionality. The Talos ISO is a bootable installer that runs Talos in memory. When you apply a machine configuration with `machine.install.image` set to a different image (e.g., a different schematic or version), the installer will:

1. Boot from the ISO (runs in memory)
2. Download the specified installer image
3. Install that image to the disk
4. Reboot into the installed image

This allows you to:

- Keep a stable ISO on USB for emergency recovery
- Install different versions/configurations by changing the machine config
- Update nodes remotely by applying new configs with different installer images

### Recommendation: Hybrid Approach

For maximum flexibility and reliability:

1. **Primary boot:** USB stick with Talos ISO (set as first boot device)
   - Provides reliable local boot option
   - Works even if network/PXE is down
   - Can be used for emergency recovery

2. **Backup boot:** PXE boot (set as second boot device)
   - Allows remote updates without physical access
   - Can serve updated images from NAS
   - Falls back if USB fails

3. **Installer image hosting:**
   - The installer image URL is constructed from Terraform: `factory.talos.dev/installer/${talos_image_factory_schematic.bare_metal.id}:v${var.talos_version}`
   - Host installer images on NAS for faster installs (download from Image Factory using schematic ID)
   - Configure machine configs to reference NAS-hosted images if desired
   - Or rely on Image Factory downloads (slower but always up-to-date)

## Remote Management Without KVM

Without a KVM (keyboard-video-mouse) switch, remote management of bare-metal nodes requires careful planning.

### Recommended Approach: Persistent USB Boot

**Setup:**

1. Keep a USB stick with Talos ISO inserted in each bare-metal node
2. Set BIOS boot order to prioritize USB
3. Configure BIOS to always attempt USB boot (don't skip on failure)

**Benefits:**

- **Remote recovery:** If a node fails, you can reboot it and it will boot from USB into maintenance mode
- **Remote reinstallation:** Reboot node → boots from USB → apply new config → installs to disk
- **No physical access needed** for most operations (except initial BIOS configuration)

**Limitations:**

- Requires initial BIOS configuration (one-time physical access)
- If BIOS settings are lost (CMOS battery failure), may need physical access to reconfigure
- USB stick could fail (keep spares)

### Alternative: IPMI/BMC (If Available)

If your bare-metal hardware supports IPMI or BMC (Baseboard Management Controller):

- **Remote console access** via IPMI web interface or `ipmitool`
- **Remote power control:** Power on/off, reset
- **Remote boot device selection:** Can change boot order remotely
- **Serial console redirection:** Access to console output

This provides the most robust remote management but requires compatible hardware.

### Talos API for Remote Management

Once Talos is installed, you can manage nodes remotely via `talosctl`:

- **Apply configurations:** `talosctl apply-config --nodes <ip> --file config.yaml`
- **Reboot nodes:** `talosctl reboot --nodes <ip>`
- **Reset nodes:** `talosctl reset --reboot --nodes <ip>`
- **View logs:** `talosctl logs --nodes <ip>`
- **Access console:** `talosctl dashboard --nodes <ip>`

**Network Requirements:**

- Nodes must be accessible on network (Talos API runs on port 50000)
- Firewall rules must allow access to Talos API
- `talosconfig` must be configured with correct endpoints

### Emergency Recovery Procedure

If a node becomes completely unresponsive:

1. **Physical access required:** Go to basement, connect monitor/keyboard
2. **Check boot status:** See if node is stuck in boot or completely powered off
3. **Force boot from USB:** If BIOS allows, select boot device manually
4. **Or reset BIOS:** Clear CMOS if boot order was lost
5. **Once booted from USB:** Node is in maintenance mode, can be managed remotely again

### Best Practices

1. **Document BIOS settings:** Take photos or notes of BIOS configuration for each node
2. **Test remote procedures:** Verify you can reboot and recover nodes remotely before you need to
3. **Keep spare USB sticks:** Have backup boot media ready
4. **Monitor node health:** Use Talos/Kubernetes monitoring to detect issues early
5. **Plan for failures:** Have a procedure documented for when physical access is needed

## Integration with Existing Cluster

### Machine Configuration Generation

Bare-metal nodes should use the same cluster configuration as VMs, but with:

1. **Different installer image** (bare-metal schematic instead of nocloud schematic)
2. **Same cluster secrets** (from `talos_machine_secrets`)
3. **Same base configuration patches** (from `talos-config.yaml`)
4. **Same network configuration** (CIDRs, VIP, etc.)

### Example: Adding Bare-Metal Worker Node

1. **Create bare-metal schematic in Terraform:**
   - Add a `talos_image_factory_schematic` resource for bare-metal nodes (see example above)
   - Use variables to specify extensions (e.g., `["intel-ucode"]` without `qemu-guest-agent`)
   - Run `terraform apply` to generate the schematic ID

2. **Generate machine config:**
   - Use the same process as VMs, but reference the bare-metal schematic ID
   - The installer image will be: `factory.talos.dev/installer/${talos_image_factory_schematic.bare_metal.id}:v${var.talos_version}`
   - This can be set via a patch similar to `common-patch.yaml.tmpl` but with the bare-metal schematic ID

3. **Apply to bare-metal node:**

   ```bash
   talosctl apply-config --insecure --nodes <bare-metal-ip> --file worker.yaml
   ```

4. **Verify node joins cluster** (same as any other worker node)

### Terraform Integration

Extend the Terraform configuration in `tf/nodes/` to support bare-metal nodes:

1. **Create separate schematic resource:**
   - Add `talos_image_factory_schematic.bare_metal` resource (as shown in example above)
   - Use a variable like `talos_bare_metal_extensions` to specify extensions (e.g., `["intel-ucode"]`)

2. **Extend machine configuration generation:**
   - Modify `tf/modules/talos-cluster/apply-talos-config.sh` or create a separate script for bare-metal nodes
   - Use the bare-metal schematic ID to construct installer image URLs
   - Generate worker configs with the appropriate installer image patch

3. **Coordinate resets with VM tainting:**
   - Add `null_resource` resources that trigger `talosctl reset` for bare-metal nodes
   - Use `depends_on` to coordinate with VM tainting
   - Or create a script that handles both VM tainting and bare-metal resets

4. **ISO/USB management:**
   - Output the bare-metal ISO URL from Terraform: `https://factory.talos.dev/image/${talos_image_factory_schematic.bare_metal.id}/v${var.talos_version}/metal-amd64.iso`
   - Use this to download and write to USB sticks
   - Consider adding a local-exec provisioner to automate USB creation (optional)

**Example Terraform structure:**

```hcl
# In tf/nodes/talos-iso.tf or new file
resource "talos_image_factory_schematic" "bare_metal" {
  # ... as shown in example above
}

# Output for use in machine configs
output "bare_metal_installer_image" {
  value = "factory.talos.dev/installer/${talos_image_factory_schematic.bare_metal.id}:v${var.talos_version}"
}

# Optional: null resource to reset bare-metal nodes
resource "null_resource" "reset_bare_metal_nodes" {
  for_each = var.bare_metal_nodes

  triggers = {
    cluster_recreate = timestamp()
  }

  provisioner "local-exec" {
    command = "talosctl reset --reboot --graceful=false --nodes ${each.value.ip_address}"
  }
}
```
