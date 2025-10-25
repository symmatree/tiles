
module "tiles-test" {
  source              = "../modules/talos-cluster"
  proxmox_storage_iso = var.proxmox_storage_iso
  cluster_name        = "tiles-test"
  start_vms           = true # Start test VMs
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
    "nuc-g3p-2" : {
      "control" : {
        vm_id       = 7320
        cores       = 1
        ram_mb      = 3000
        mac_address = "BC:24:11:D0:73:20"
        ip_address  = "10.0.105.32"
      },
      "worker" : {
        vm_id       = 8320
        cores       = 3
        ram_mb      = 11000
        mac_address = "BC:24:11:D0:83:20"
        ip_address  = "10.0.105.52"
      }
    },
  }
}
