

module "tiles-test" {
  source                 = "../modules/talos-cluster"
  proxmox_storage_iso    = var.proxmox_storage_iso
  cluster_name           = "tiles-test"
  start_vms              = true
  apply_configs          = true
  run_bootstrap          = true
  onepassword_vault      = data.onepassword_vault.tf_secrets.uuid
  onepassword_vault_name = data.onepassword_vault.tf_secrets.name
  talos                  = local.talos_configs["test"]
  nodes_to_iso_ids = {
    for node_name in data.proxmox_virtual_environment_nodes.nodes.names :
    node_name => local.nodes_to_iso_ids[node_name]["test"]
  }

  external_ip_cidr  = "10.0.106.0/24"
  pod_cidr          = "10.0.107.0/24"
  service_cidr      = "10.0.108.0/24"
  control_plane_vip = "10.0.105.10"
  vms               = local.test_vms
}

module "k8s-test" {
  source            = "../modules/k8s-cluster"
  project_id        = var.project_id
  cluster_name      = "tiles-test"
  onepassword_vault = data.onepassword_vault.tf_secrets.uuid
}

output "test_machine_secrets" {
  description = "Talos machine secrets"
  value       = module.tiles-test.machine_secrets
  sensitive   = true
}

output "test_talosconfig" {
  description = "Talos client configuration"
  value       = module.tiles-test.talosconfig
  sensitive   = true
}

output "test_control_plane_config" {
  description = "Control plane machine configuration"
  value       = module.tiles-test.control_plane_config
  sensitive   = true
}

output "test_worker_config" {
  description = "Worker machine configuration"
  value       = module.tiles-test.worker_config
  sensitive   = true
}

output "test_control_plane_ips" {
  description = "Control plane IP addresses"
  value       = module.tiles-test.control_plane_ips
}

output "test_control_plane_vip" {
  description = "Control plane VIP"
  value       = module.tiles-test.control_plane_vip
}

output "test_bootstrap_node" {
  description = "Node that was bootstrapped (only when VMs are started)"
  value       = module.tiles-test.bootstrap_node
}

output "test_cluster_endpoint" {
  description = "Cluster API endpoint"
  value       = module.tiles-test.cluster_endpoint
}

output "test_vms_started" {
  description = "Whether VMs are started and cluster is operational"
  value       = module.tiles-test.vms_started
}
