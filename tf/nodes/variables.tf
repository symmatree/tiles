# Proxmox provider configuration
variable "proxmox_endpoint" {
  description = "Proxmox VE API endpoint (e.g., https://pve.local.symmatree.com:8006/)"
  type        = string
}

variable "proxmox_username" {
  description = "Proxmox VE username (e.g., root@pam)"
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

variable "proxmox_ssh_private_key_path" {
  description = "Path to SSH private key for Proxmox host"
  type        = string
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

variable "unifi_username" {
  description = "Username for service account"
  type        = string
  default     = "terraform"
}

variable "unifi_password" {
  description = "Unifi: Password for service account"
  type        = string
  sensitive   = true
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
# variable "talos_schematic" {
#   description = "The Talos schematic hash to use for downloading the ISO."
#   type        = string
# }

variable "cluster_name" {
  description = "Name prefix for the Talos cluster"
  type        = string
  default     = "talos"
}

# Network configuration
variable "network_gateway" {
  description = "Network gateway IP address"
  type        = string
  default     = "10.0.1.1"
}

variable "network_cidr_bits" {
  description = "Network CIDR bits (e.g., 24 for /24)"
  type        = number
  default     = 24
}

# Control plane configuration
variable "control_plane_count" {
  description = "Number of control plane nodes"
  type        = number
  default     = 1
}

variable "control_plane_cpu_cores" {
  description = "Number of CPU cores for control plane nodes"
  type        = number
  default     = 2
}

variable "control_plane_memory_mb" {
  description = "Memory in MB for control plane nodes"
  type        = number
  default     = 4096
}

variable "control_plane_disk_size_gb" {
  description = "Disk size in GB for control plane nodes"
  type        = number
  default     = 50
}

variable "control_plane_vm_id_start" {
  description = "Starting VM ID for control plane nodes"
  type        = number
  default     = 100
}

variable "control_plane_ips" {
  description = "List of IP addresses for control plane nodes"
  type        = list(string)
  default     = ["10.0.1.50"]
}

variable "control_plane_mac_addresses" {
  description = "List of MAC addresses for control plane nodes (optional)"
  type        = list(string)
  default     = []
}

# Worker configuration
variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 1
}

variable "worker_cpu_cores" {
  description = "Number of CPU cores for worker nodes"
  type        = number
  default     = 2
}

variable "worker_memory_mb" {
  description = "Memory in MB for worker nodes"
  type        = number
  default     = 4096
}

variable "worker_disk_size_gb" {
  description = "Disk size in GB for worker nodes"
  type        = number
  default     = 100
}

variable "worker_vm_id_start" {
  description = "Starting VM ID for worker nodes"
  type        = number
  default     = 200
}

variable "worker_ips" {
  description = "List of IP addresses for worker nodes"
  type        = list(string)
  default     = ["10.0.1.51"]
}

variable "worker_mac_addresses" {
  description = "List of MAC addresses for worker nodes (optional)"
  type        = list(string)
  default     = []
}
