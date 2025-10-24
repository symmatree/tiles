
module "tiles-prod" {
  source              = "../modules/talos-cluster"
  proxmox_storage_iso = var.proxmox_storage_iso
  cluster_name        = "tiles"
  start_vms           = false  # Don't start prod VMs yet
  talos = {
    version   = var.talos_version
    variant   = var.talos_variant
    arch      = var.talos_arch
    schematic = talos_image_factory_schematic.this.id
  }

  # Network configuration for tiles cluster (10.0.101.0/22 block)
  pod_cidr          = "10.0.103.0/24"
  service_cidr      = "10.0.104.0/24"
  control_plane_vip = "10.0.101.10"

  node_config = {
    "nuc-g2p-1" : {
      "control" : {
        vm_id       = 7210
        cores       = 1
        ram_mb      = 3000
        mac_address = "BC:24:11:D0:72:10"
        ip_address  = "10.0.101.21"
      },
      "worker" : {
        vm_id       = 8210
        cores       = 3
        ram_mb      = 7000
        mac_address = "BC:24:11:D0:82:10"
        ip_address  = "10.0.101.41"
      }
    },
    "nuc-g2p-2" : {
      "control" : {
        vm_id       = 7220
        cores       = 1
        ram_mb      = 3000
        mac_address = "BC:24:11:D0:72:20"
        ip_address  = "10.0.101.22"
      },
      "worker" : {
        vm_id       = 8220
        cores       = 3
        ram_mb      = 7000
        mac_address = "BC:24:11:D0:82:20"
        ip_address  = "10.0.101.42"
      }
    },
    "nuc-g3p-1" : {
      "control" : {
        vm_id       = 7310
        cores       = 1
        ram_mb      = 3000
        mac_address = "BC:24:11:D0:73:10"
        ip_address  = "10.0.101.31"
      },
      "worker" : {
        vm_id       = 8310
        cores       = 3
        ram_mb      = 11000
        mac_address = "BC:24:11:D0:83:10"
        ip_address  = "10.0.101.51"
      }
    },
  }
}
