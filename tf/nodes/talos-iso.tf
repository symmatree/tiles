data "talos_image_factory_extensions_versions" "this" {
  talos_version = "v${var.talos_version}"
  filters = {
    names = var.talos_schematic_extensions
  }
}

resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode(
    {
      customization = {
        systemExtensions = {
          officialExtensions = data.talos_image_factory_extensions_versions.this.extensions_info.*.name
        }
        extraKernelArgs = var.talos_schematic_extra_kernel_args
      }
    }
  )
}

output "schematic_id" {
  value = talos_image_factory_schematic.this.id
}

locals {
  filename = "talos-v${var.talos_version}-${var.talos_variant}-${var.talos_arch}-${talos_image_factory_schematic.this.id}.iso"
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

  url       = "https://factory.talos.dev/image/${talos_image_factory_schematic.this.id}/v${var.talos_version}/${var.talos_variant}-${var.talos_arch}.iso"
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
