
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

#   # Network configuration for tiles cluster (10.0.101.0/22 block)
#   pod_cidr          = "10.0.103.0/24"
#   service_cidr      = "10.0.104.0/24"
#   control_plane_vip = "10.0.101.10"

# }



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
