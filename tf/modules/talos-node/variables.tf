variable "proxmox_node_name" {
  description = "Proxmox node name"
  type        = string
}
variable "proxmox_storage_iso" {
  description = "Proxmox storage for ISO files"
  type        = string
  default     = "local"
}

variable "cluster_name" {
  description = "Talos cluster name"
  type        = string
}

variable "talos" {
  description = "Talos configuration"
  type = object({
    version   = string
    variant   = string
    arch      = string
    schematic = string
  })
}

variable "vm_config" {
  description = "Config for the VMs"
  type = map(object({
    vm_id       = number
    cores       = number
    ram_mb      = number
    mac_address = string
    ip_address  = string
  }))
}
