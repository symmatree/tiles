
locals {
  test_vms = {
    "tiles-test-cp" : {
      type              = "control"
      proxmox_node_name = "nuc-g3p-2"
      vm_id             = 7411
      cores             = 1
      ram_mb            = 3000
      mac_address       = "bc:24:11:d0:74:11"
      ip_address        = "10.0.192.11"
    }
    "tiles-test-wk" : {
      type              = "worker"
      proxmox_node_name = "nuc-g3p-2"
      vm_id             = 7421
      cores             = 3
      ram_mb            = 11000
      mac_address       = "bc:24:11:d0:74:21"
      ip_address        = "10.0.192.21"
    }
  }
}
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

  external_ip_cidr  = "10.0.193.0/24"
  pod_cidr          = "10.0.208.0/20"
  service_cidr      = "10.0.200.0/21"
  control_plane_vip = "10.0.192.10"
  vms               = local.test_vms
}

module "k8s-test" {
  source            = "../modules/k8s-cluster"
  project_id        = var.project_id
  cluster_name      = "tiles-test"
  onepassword_vault = data.onepassword_vault.tf_secrets.uuid

  # OAuth configuration for ArgoCD
  argocd_url = "https://argocd.tiles-test.symmatree.com"
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
