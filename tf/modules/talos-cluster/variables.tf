
variable "nodes_to_iso_ids" {
  description = "Map of Proxmox nodes to their Talos ISO IDs"
  type        = map(string)
}

variable "vms" {
  description = "List of VMs in the cluster"
  type = map(object({
    type              = string # "control" or "worker"
    proxmox_node_name = string
    vm_id             = number
    cores             = number
    ram_mb            = number
    mac_address       = string
    ip_address        = string
    taint             = string
  }))
}

variable "unifi_network_id" {
  description = "Unifi network ID for the metal node"
  type        = string
}

variable "metal_amd_nodes" {
  description = "List of metal AMD nodes in the cluster"
  type = map(object({
    name        = string
    type        = string
    mac_address = string
    ip_address  = string
    taint       = string
  }))
}

variable "cluster_name" {
  description = "Talos cluster name"
  type        = string
}

variable "proxmox_storage_iso" {
  description = "Proxmox storage for ISO files"
  type        = string
}

variable "talos_version" {
  description = "Talos Linux version"
  type        = string
}

variable "talos_arch" {
  description = "Talos Linux architecture (e.g., amd64, arm64)"
  type        = string
}

variable "talos_vm_variant" {
  description = "Talos Linux variant for VMs (e.g., nocloud)"
  type        = string
  default     = "nocloud"
}

variable "talos_vm_schematic" {
  description = "Talos Linux schematic ID for VMs"
  type        = string
}

variable "talos_metal_amd_variant" {
  description = "Talos Linux variant for bare metal AMD (e.g., metal)"
  type        = string
  default     = "metal"
}

variable "talos_metal_amd_schematic" {
  description = "Talos Linux schematic ID for bare metal AMD"
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
  description = "Control plane VIP for the cluster"
  type        = string
}

variable "control_plane_vip_link" {
  description = "Network interface name for the control plane VIP (e.g., 'ens18' for virtio-net). Required for Talos v1.12+ which uses Layer2VIPConfig."
  type        = string
}

variable "external_ip_cidr" {
  description = "External IP CIDR for the cluster"
  type        = string
}

variable "onepassword_vault" {
  description = "1Password vault UUID."
  type        = string
}

variable "onepassword_vault_name" {
  description = "1Password vault name (e.g., 'tiles-secrets')."
  type        = string
}

variable "admin_user" {
  description = "Admin user email"
  type        = string
}
