

module "cluster" {
  source                 = "../modules/talos-cluster"
  proxmox_storage_iso    = var.proxmox_storage_iso
  cluster_name           = var.cluster_name
  start_vms              = true
  apply_configs          = true
  run_bootstrap          = true
  onepassword_vault      = data.onepassword_vault.tf_secrets.uuid
  onepassword_vault_name = data.onepassword_vault.tf_secrets.name
  talos = {
    version   = var.talos_version
    variant   = var.talos_variant
    arch      = var.talos_arch
    schematic = talos_image_factory_schematic.this.id
  }

  admin_user        = var.admin_user
  external_ip_cidr  = var.external_ip_cidr
  pod_cidr          = var.pod_cidr
  service_cidr      = var.service_cidr
  control_plane_vip = var.control_plane_vip
  vms               = var.virtual_machines
  nodes_to_iso_ids  = local.nodes_to_iso_ids
  main_project_id   = local.main_project_id
  kms_project_id    = local.kms_project_id
  gcp_region        = var.gcp_region
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

output "control_plane_ips" {
  description = "Control plane IP addresses"
  value       = module.cluster.control_plane_ips
}

output "control_plane_vip" {
  description = "Control plane VIP"
  value       = module.cluster.control_plane_vip
}

output "bootstrap_node" {
  description = "Node that was bootstrapped (only when VMs are started)"
  value       = module.cluster.bootstrap_node
}

output "cluster_endpoint" {
  description = "Cluster API endpoint"
  value       = module.cluster.cluster_endpoint
}

output "vms_started" {
  description = "Whether VMs are started and cluster is operational"
  value       = module.cluster.vms_started
}
