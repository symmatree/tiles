# Proxmox provider configuration
variable "proxmox_endpoint" {
  description = "Proxmox VE API endpoint (e.g., https://pve.local.symmatree.com:8006/)"
  type        = string
}

variable "proxmox_insecure" {
  description = "Skip TLS verification for Proxmox API"
  type        = bool
  default     = true
}

variable "proxmox_ssh_username" {
  description = "SSH username for Proxmox host"
  type        = string
  default     = "root"
}

variable "proxmox_storage_iso" {
  description = "Proxmox storage for ISO files"
  type        = string
  default     = "local"
}

variable "proxmox_storage_vm" {
  description = "Proxmox storage for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "unifi_controller_url" {
  description = "Unifi Controller URL"
  type        = string
  default     = "https://morpheus.local.symmatree.com:443"
}

variable "proxmox_network_bridge" {
  description = "Proxmox network bridge"
  type        = string
  default     = "vmbr0"
}

# Talos configuration
variable "talos_version" {
  description = "Talos Linux version"
  type        = string
}
variable "talos_variant" {
  description = "The Talos variant to use (e.g., 'metal')."
  type        = string
}

variable "talos_arch" {
  description = "The Talos architecture to use (e.g., 'amd64' or 'arm64')."
  type        = string
  default     = "amd64"
}
