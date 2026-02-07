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
}

variable "unifi_controller_url" {
  description = "Unifi Controller URL"
  type        = string
}

# Talos configuration
variable "talos_version" {
  description = "Talos Linux version"
  type        = string
}

variable "talos_vm_variant" {
  description = "Talos Linux variant (e.g., nocloud, metal)"
  type        = string
}

variable "talos_arch" {
  description = "Talos Linux architecture (e.g., amd64, arm64)"
  type        = string
}

variable "talos_metal_amd_variant" {
  description = "Talos Linux variant for bare metal AMD (e.g., metal)"
  type        = string
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
    taint             = string
  }))
}

variable "unifi_network_name" {
  description = "Unifi network name"
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

variable "cluster_nfs_path" {
  description = "NFS export path for the cluster's shared NFS storage (e.g., /volume2/tiles or /volume2/tiles-test). This should match the Synology NFS export path, which includes the volume name."
  type        = string
}

variable "datasets_nfs_path" {
  description = "NFS export path for the datasets share (e.g., /volume2/datasets). This is common to both clusters."
  type        = string
}

variable "nfs_server" {
  description = "NFS server hostname or IP address"
  type        = string
}

variable "seed_project_id" {
  description = "GCP seed project ID (symm-custodes) where shared DNS zones are located"
  type        = string
}

variable "dns_zone_ad_local" {
  description = "DNS zone name for ad.local.symmatree.com in seed project"
  type        = string
}

variable "dns_zone_local" {
  description = "DNS zone name for local.symmatree.com in seed project"
  type        = string
}

variable "proxmox_root_password" {
  description = "Proxmox root@pam password (required for bind mounts)"
  type        = string
  sensitive   = true
}
