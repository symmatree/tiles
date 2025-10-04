# Proxmox provider configuration
variable "proxmox_endpoint" {
  description = "Proxmox VE API endpoint (e.g., https://pve.local.symmatree.com:8006/)"
  type        = string
}

variable "proxmox_username" {
  description = "Proxmox VE username (e.g., root@pam)"
  type        = string
}

variable "proxmox_password" {
  description = "Proxmox VE password"
  type        = string
  sensitive   = true
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

variable "proxmox_node_name" {
  description = "Proxmox node name where VMs will be created"
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

variable "proxmox_network_bridge" {
  description = "Proxmox network bridge"
  type        = string
  default     = "vmbr0"
}

# Talos configuration
variable "talos_version" {
  description = "Talos Linux version"
  type        = string
  default     = "1.9.5"
}

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

variable "dns_servers" {
  description = "List of DNS servers"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
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
