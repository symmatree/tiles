variable "proxmox_storage_iso" {
  description = "Proxmox storage for ISO files"
  type        = string
  default     = "local"
}

variable "unifi_controller_url" {
  description = "Unifi Controller URL"
  type        = string
  default     = "https://morpheus.local.symmatree.com:443"
}

# Talos configuration
variable "talos_version" {
  description = "Talos Linux version"
  type        = string
}
