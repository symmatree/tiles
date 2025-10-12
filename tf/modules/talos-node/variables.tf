variable "proxmox_node_name" {
  description = "Proxmox node name"
  type        = string
}
variable "proxmox_storage_iso" {
  description = "Proxmox storage for ISO files"
  type        = string
  default     = "local"
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
variable "talos_schematic" {
  description = "The Talos schematic hash to use for downloading the ISO."
  type        = string
}

# Control plane VM configuration
variable "control_vm_id" {
  description = "VM ID for the control plane node"
  type        = number
}

variable "control_cores" {
  description = "Number of CPU cores for the control plane VM"
  type        = number
  default     = 1
}

variable "control_ram" {
  description = "Amount of RAM in MB for the control plane VM"
  type        = number
}

variable "control_mac_address" {
  description = "MAC address for the control plane VM network interface"
  type        = string
}

# Worker node VM configuration
variable "worker_vm_id" {
  description = "VM ID for the worker node"
  type        = number
}

variable "worker_cores" {
  description = "Number of CPU cores for the worker VM"
  type        = number
  default     = 3
}

variable "worker_ram" {
  description = "Amount of RAM in MB for the worker VM"
  type        = number
}

variable "worker_mac_address" {
  description = "MAC address for the worker VM network interface"
  type        = string
}
