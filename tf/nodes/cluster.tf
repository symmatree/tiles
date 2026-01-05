

module "cluster" {
  source                    = "../modules/talos-cluster"
  proxmox_storage_iso       = var.proxmox_storage_iso
  cluster_name              = var.cluster_name
  onepassword_vault         = data.onepassword_vault.tf_secrets.uuid
  onepassword_vault_name    = data.onepassword_vault.tf_secrets.name
  talos_version             = var.talos_version
  talos_arch                = var.talos_arch
  talos_vm_variant          = var.talos_vm_variant
  talos_vm_schematic        = talos_image_factory_schematic.vm.id
  talos_metal_amd_variant   = var.talos_metal_amd_variant
  talos_metal_amd_schematic = talos_image_factory_schematic.metal_amd.id

  admin_user             = var.admin_user
  external_ip_cidr       = var.external_ip_cidr
  pod_cidr               = var.pod_cidr
  service_cidr           = var.service_cidr
  control_plane_vip      = var.control_plane_vip
  control_plane_vip_link = "eth0" # This depends on predictable network ifaces being off
  vms                    = var.virtual_machines
  metal_amd_nodes        = var.metal_amd_nodes
  nodes_to_iso_ids       = local.nodes_to_iso_ids
  main_project_id        = local.main_project_id
  kms_project_id         = local.kms_project_id
  gcp_region             = var.gcp_region
  cluster_nfs_path       = var.cluster_nfs_path
  datasets_nfs_path      = var.datasets_nfs_path
  nfs_server             = var.nfs_server
}

output "talosconfig" {
  description = "Talos client configuration"
  value       = module.cluster.talosconfig
  sensitive   = true
}

output "control_plane_config" {
  description = "Control plane machine configuration"
  value       = module.cluster.control_plane_config
  sensitive   = true
}

output "worker_config" {
  description = "Worker machine configuration"
  value       = module.cluster.worker_config
  sensitive   = true
}

output "control_plane_vip" {
  description = "Control plane VIP"
  value       = module.cluster.control_plane_vip
}

output "all_node_ips" {
  description = "All cluster node IP addresses (for NFS access configuration)"
  value       = concat([for vm in var.virtual_machines : vm.ip_address], [for node in var.metal_amd_nodes : node.ip_address])
}
