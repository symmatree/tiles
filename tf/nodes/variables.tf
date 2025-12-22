variable "cluster_name" {
  description = "Cluster name"
  type        = string
}

variable "cluster_code" {
  description = "One-letter cluster code"
  type        = string
  validation {
    condition     = length(var.cluster_code) == 1
    error_message = "Cluster code must be one letter."
  }
}

variable "admin_user" {
  description = "Admin user email"
  type        = string
}

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

variable "talos_variant" {
  description = "Talos Linux variant (e.g., nocloud, metal)"
  type        = string
}

variable "talos_arch" {
  description = "Talos Linux architecture (e.g., amd64, arm64)"
  type        = string
}

variable "talos_schematic_extensions" {
  description = "List of Talos system extensions to include in the schematic"
  type        = list(string)
  default     = ["qemu-guest-agent"]
}

variable "talos_schematic_extra_kernel_args" {
  description = "Extra kernel arguments for Talos schematic"
  type        = list(string)
  default     = ["vga=792", "-talos.halt_if_installed"]
}

variable "gcp_region" {
  description = "Google Cloud region"
  type        = string
}

variable "virtual_machines" {
  description = "List of VMs to create"
  type = map(object({
    type              = string # "control" or "worker"
    proxmox_node_name = string
    vm_id             = number
    cores             = number
    ram_mb            = number
    mac_address       = string
    ip_address        = string
  }))
}

variable "external_ip_cidr" {
  description = "External IP CIDR for the cluster"
  type        = string
}

variable "pod_cidr" {
  description = "Pod CIDR for the cluster"
  type        = string
}

variable "service_cidr" {
  description = "Service CIDR for the cluster"
  type        = string
}

variable "control_plane_vip" {
  description = "Control plane VIP address"
  type        = string
}
