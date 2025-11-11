variable "proxmox_node_name" {
  description = "Proxmox node name"
  type        = string
}

variable "proxmox_storage_iso" {
  description = "Proxmox storage for ISO files"
  type        = string
  default     = "local"
}

variable "talos_configs" {
  description = "List of Talos configurations to download ISOs for"
  type = map(object({
    version   = string
    variant   = string
    arch      = string
    schematic = string
  }))
}
