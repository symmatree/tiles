# VM schematic (for Proxmox VMs)
data "talos_image_factory_extensions_versions" "vm" {
  talos_version = "v${var.talos_version}"
  filters = {
    names = ["qemu-guest-agent"]
  }
}

resource "talos_image_factory_schematic" "vm" {
  schematic = yamlencode(
    {
      customization = {
        systemExtensions = {
          officialExtensions = data.talos_image_factory_extensions_versions.vm.extensions_info.*.name
        }
        extraKernelArgs = ["vga=792", "-talos.halt_if_installed"]
      }
    }
  )
}

# Bare-metal AMD schematic (for AMD Ryzen APUs)
data "talos_image_factory_extensions_versions" "metal_amd" {
  talos_version = "v${var.talos_version}"
  filters = {
    names = ["amd-ucode", "amdgpu", "amdgpu-firmware"]
  }
}

resource "talos_image_factory_schematic" "metal_amd" {
  schematic = yamlencode(
    {
      customization = {
        systemExtensions = {
          officialExtensions = data.talos_image_factory_extensions_versions.metal_amd.extensions_info.*.name
        }
        extraKernelArgs = ["-talos.halt_if_installed"]
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

locals {
  filename = "talos-${var.cluster_code}-v${var.talos_version}-${var.talos_vm_variant}-${var.talos_arch}-${talos_image_factory_schematic.vm.id}.iso"
}

# Download Talos ISOs to each Proxmox node
# Inlined from talos-node module - original structure was:
#   module called once per node, resource inside iterated over talos_configs
#   With workspaces, we only have one config, so this creates one resource per node
resource "proxmox_virtual_environment_download_file" "talos_iso" {
  for_each = toset(data.proxmox_virtual_environment_nodes.nodes.names)

  content_type = "iso"
  datastore_id = var.proxmox_storage_iso
  node_name    = each.value

  url       = "https://factory.talos.dev/image/${talos_image_factory_schematic.vm.id}/v${var.talos_version}/${var.talos_vm_variant}-${var.talos_arch}.iso"
  file_name = local.filename
  overwrite = true
}

locals {
  # Map of Proxmox node names to ISO IDs (required by talos-cluster module)
  nodes_to_iso_ids = {
    for node_name in data.proxmox_virtual_environment_nodes.nodes.names : node_name =>
    proxmox_virtual_environment_download_file.talos_iso[node_name].id
  }
}
