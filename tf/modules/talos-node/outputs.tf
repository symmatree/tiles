output "iso_ids" {
  description = "Map of ISO IDs keyed by version-variant-arch"
  value = {
    for k, v in proxmox_virtual_environment_download_file.talos_iso : k => v.id
  }
}
