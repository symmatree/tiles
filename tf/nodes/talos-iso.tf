# Official extension names for each schematic, pinned rather than resolved from the image
# factory at plan time.
#
# These were read from the talos_image_factory_extensions_versions data sources they replace,
# and produce byte-identical schematics: the same three schematic IDs, so the same images.
# A name is not tied to a Talos version -- the version is bound in the image URL
# (/image/<schematic>/v<version>/...), not in the schematic -- so a talos_version bump needs
# no change here.
#
# Pinned because a data source is re-read on every plan, including with -refresh=false, which
# made every plan depend on reaching factory.talos.dev from the GitHub runner. The schematic
# resources below do not: their Read is a no-op, so they only contact the factory when a
# schematic actually changes, and the Proxmox hosts (not the runner) fetch the images.
#
# amdgpu-firmware is deliberately absent: no such official extension exists for this Talos
# version, so the filter it replaced silently matched nothing. Adding a name that the factory
# does not know now fails loudly when the schematic is next created.

# talos.dashboard.disabled=1 on every schematic: the console dashboard polls machined
# over the local unix socket every 5s (NetworkDeviceStats, CPUInfo, CPUFreqStats,
# SystemStat, Memory, LoadAvg, ServiceList, Processes), and machined logs three lines per
# call -- two authz grants and a success record. That is ~19.4k lines/hour/node, which was
# 53% of all Loki ingest across the eight nodes (#774). Disabling it also stops Talos
# redirecting kernel logs to /dev/tty1, so the KVM console shows kernel output instead of
# the dashboard. Kernel args live in the schematic, not machine.install.extraKernelArgs --
# see the install block in tf/modules/talos-cluster/talos-config.yaml for why.

locals {
  talos_extensions_vm          = ["siderolabs/qemu-guest-agent"]
  talos_extensions_metal_amd   = ["siderolabs/amdgpu", "siderolabs/amd-ucode"]
  talos_extensions_metal_intel = ["siderolabs/i915", "siderolabs/intel-ucode"]
}

# VM schematic (for Proxmox VMs)
resource "talos_image_factory_schematic" "vm" {
  schematic = yamlencode(
    {
      customization = {
        systemExtensions = {
          officialExtensions = local.talos_extensions_vm
        }
        extraKernelArgs = ["vga=792", "net.ifnames=0", "-talos.halt_if_installed", "talos.dashboard.disabled=1"]
      }
    }
  )
}

# Bare-metal AMD schematic (for AMD Ryzen APUs)
resource "talos_image_factory_schematic" "metal_amd" {
  schematic = yamlencode(
    {
      customization = {
        systemExtensions = {
          officialExtensions = local.talos_extensions_metal_amd
        }
        extraKernelArgs = ["net.ifnames=0", "-talos.halt_if_installed", "talos.dashboard.disabled=1"]
      }
    }
  )
}

# Bare-metal Intel schematic (e.g. Alder Lake-N integrated graphics)
resource "talos_image_factory_schematic" "metal_intel" {
  schematic = yamlencode(
    {
      customization = {
        systemExtensions = {
          officialExtensions = local.talos_extensions_metal_intel
        }
        extraKernelArgs = ["net.ifnames=0", "-talos.halt_if_installed", "talos.dashboard.disabled=1"]
      }
    }
  )
}

output "vm_schematic_id" {
  description = "Schematic ID for VM installations"
  value       = talos_image_factory_schematic.vm.id
}

output "metal_amd_schematic_id" {
  description = "Schematic ID for bare-metal AMD installations"
  value       = talos_image_factory_schematic.metal_amd.id
}

output "metal_amd_iso_url" {
  description = "Download URL for bare-metal AMD ISO"
  value       = "https://factory.talos.dev/image/${talos_image_factory_schematic.metal_amd.id}/v${var.talos_version}/metal-amd64.iso"
}

output "metal_intel_schematic_id" {
  description = "Schematic ID for bare-metal Intel installations"
  value       = talos_image_factory_schematic.metal_intel.id
}

output "metal_intel_iso_url" {
  description = "Download URL for bare-metal Intel ISO"
  value       = "https://factory.talos.dev/image/${talos_image_factory_schematic.metal_intel.id}/v${var.talos_version}/metal-amd64.iso"
}

locals {
  filename = "talos-${var.cluster_code}-v${var.talos_version}-${var.talos_vm_variant}-${var.talos_arch}-${talos_image_factory_schematic.vm.id}.iso"
}

# Download Talos ISOs to each Proxmox node
# Inlined from talos-node module - original structure was:
#   module called once per node, resource inside iterated over talos_configs
#   With workspaces, we only have one config, so this creates one resource per node
resource "proxmox_download_file" "talos_iso" {
  for_each = toset(data.proxmox_virtual_environment_nodes.nodes.names)

  content_type = "iso"
  datastore_id = var.proxmox_storage_iso
  node_name    = each.value

  url       = "https://factory.talos.dev/image/${talos_image_factory_schematic.vm.id}/v${var.talos_version}/${var.talos_vm_variant}-${var.talos_arch}.iso"
  file_name = local.filename
  overwrite = true
}

moved {
  from = proxmox_virtual_environment_download_file.talos_iso
  to   = proxmox_download_file.talos_iso
}

locals {
  # Map of Proxmox node names to ISO IDs (required by talos-cluster module)
  nodes_to_iso_ids = {
    for node_name in data.proxmox_virtual_environment_nodes.nodes.names : node_name =>
    proxmox_download_file.talos_iso[node_name].id
  }
}
