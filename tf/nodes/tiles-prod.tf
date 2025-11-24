
# module "tiles-prod" {
#   source              = "../modules/talos-cluster"
#   proxmox_storage_iso = var.proxmox_storage_iso
#   cluster_name        = "tiles"
#   start_vms           = false # Don't start prod VMs yet
#   onepassword_vault   = data.onepassword_vault.tf_secrets.uuid
#   talos = {
#     version   = var.talos_version
#     schematic = talos_image_factory_schematic.this.id
#   }

#   # Network configuration for tiles cluster (10.0.128.0/18 block)
#   external_ip_cidr  = "10.0.129.0/24"
#   pod_cidr          = "10.0.144.0/20"
#   service_cidr      = "10.0.136.0/21"
#   control_plane_vip = "10.0.128.10"

# }

locals {
  prod_vms = {
    "tiles-cp-1" : {
      type              = "control"
      proxmox_node_name = "nuc-g2p-1"
      vm_id             = 7211
      cores             = 1
      ram_mb            = 3000
      mac_address       = "bc:24:11:d0:72:11"
      ip_address        = "10.0.128.11"
    }
    "tiles-cp-2" : {
      type              = "control"
      proxmox_node_name = "nuc-g2p-2"
      vm_id             = 7212
      cores             = 1
      ram_mb            = 3000
      mac_address       = "bc:24:11:d0:72:12"
      ip_address        = "10.0.128.12"
    }
    "tiles-cp-3" : {
      type              = "control"
      proxmox_node_name = "nuc-g3p-1"
      vm_id             = 7213
      cores             = 1
      ram_mb            = 3000
      mac_address       = "bc:24:11:d0:72:13"
      ip_address        = "10.0.128.13"
    }
    "tiles-wk-1" : {
      type              = "worker"
      proxmox_node_name = "nuc-g2p-1"
      vm_id             = 7221
      cores             = 3
      ram_mb            = 7000
      mac_address       = "bc:24:11:d0:72:21"
      ip_address        = "10.0.128.21"
    }
    "tiles-wk-2" : {
      type              = "worker"
      proxmox_node_name = "nuc-g2p-2"
      vm_id             = 7222
      cores             = 3
      ram_mb            = 7000
      mac_address       = "bc:24:11:d0:72:22"
      ip_address        = "10.0.128.22"
    }
    "tiles-wk-3" : {
      type              = "worker"
      proxmox_node_name = "nuc-g3p-1"
      vm_id             = 7223
      cores             = 3
      ram_mb            = 11000
      mac_address       = "bc:24:11:d0:72:23"
      ip_address        = "10.0.128.23"
    }
  }
}


# output "tiles_talosconfig" {
#   description = "Talos client configuration"
#   value       = module.tiles-prod.talosconfig
#   sensitive   = true
# }

# output "tiles_control_plane_config" {
#   description = "Control plane machine configuration"
#   value       = module.tiles-prod.control_plane_config
#   sensitive   = true
# }

# output "tiles_worker_config" {
#   description = "Worker machine configuration"
#   value       = module.tiles-prod.worker_config
#   sensitive   = true
# }

# output "tiles_control_plane_ips" {
#   description = "Control plane IP addresses"
#   value       = module.tiles-prod.control_plane_ips
# }

# output "tiles_control_plane_vip" {
#   description = "Control plane VIP"
#   value       = module.tiles-prod.control_plane_vip
# }

# output "tiles_bootstrap_node" {
#   description = "Node that was bootstrapped (only when VMs are started)"
#   value       = module.tiles-prod.bootstrap_node
# }

# output "tiles_cluster_endpoint" {
#   description = "Cluster API endpoint"
#   value       = module.tiles-prod.cluster_endpoint
# }

# output "tiles_vms_started" {
#   description = "Whether VMs are started and cluster is operational"
#   value       = module.tiles-prod.vms_started
# }
