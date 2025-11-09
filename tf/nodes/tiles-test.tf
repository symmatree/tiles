
module "tiles-test" {
  source              = "../modules/talos-cluster"
  proxmox_storage_iso = var.proxmox_storage_iso
  cluster_name        = "tiles-test"
  start_vms           = true
  run_bootstrap       = false
  apply_configs       = false
  onepassword_vault   = data.onepassword_vault.tf_secrets.uuid
  talos = {
    version   = var.talos_version
    variant   = var.talos_variant
    arch      = var.talos_arch
    schematic = talos_image_factory_schematic.this.id
  }

  # Network configuration for tiles-test cluster (10.0.105.0/22 block)
  pod_cidr          = "10.0.107.0/24"
  service_cidr      = "10.0.108.0/24"
  control_plane_vip = "10.0.105.10"
  node_config = {
    "nuc-g3p-2" = {
      control_planes = [
        {
          vm_id       = 7320
          cores       = 1
          ram_mb      = 3000
          mac_address = "BC:24:11:D0:73:20"
          ip_address  = "10.0.105.32"
        }
      ]
      workers = [
        {
          vm_id       = 8320
          cores       = 3
          ram_mb      = 11000
          mac_address = "BC:24:11:D0:83:20"
          ip_address  = "10.0.105.52"
        }
      ]
    }
  }
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
