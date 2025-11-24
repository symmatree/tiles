
# Upload Talos ISOs to Proxmox node
resource "proxmox_virtual_environment_download_file" "talos_iso" {
  for_each = var.talos_configs

  content_type = "iso"
  datastore_id = var.proxmox_storage_iso
  node_name    = var.proxmox_node_name

  url       = "https://factory.talos.dev/image/${each.value.schematic}/v${each.value.version}/${each.value.variant}-${each.value.arch}.iso"
  file_name = "talos-${each.key}-${each.value.version}.iso"
  overwrite = true
}
