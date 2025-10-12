
locals {
  node_config = {
    "nuc-g2p-1" : {
      "control" : {
        vm_id       = 7210
        cores       = 1
        ram_mb      = 3000
        mac_address = "BC:24:11:D0:72:10"
        ip_address  = "10.0.7.21"
      },
      "worker" : {
        vm_id       = 8210
        cores       = 3
        ram_mb      = 7000
        mac_address = "BC:24:11:D0:82:10"
        ip_address  = "10.0.8.21"
      }
    },
    "nuc-g2p-2" : {
      "control" : {
        vm_id       = 7220
        cores       = 1
        ram_mb      = 3000
        mac_address = "BC:24:11:D0:72:20"
        ip_address  = "10.0.7.22"
      },
      "worker" : {
        vm_id       = 8220
        cores       = 3
        ram_mb      = 7000
        mac_address = "BC:24:11:D0:82:20"
        ip_address  = "10.0.8.22"
      }
    },
    "nuc-g3p-1" : {
      "control" : {
        vm_id       = 7310
        cores       = 1
        ram_mb      = 3000
        mac_address = "BC:24:11:D0:73:10"
        ip_address  = "10.0.7.31"
      },
      "worker" : {
        vm_id       = 8310
        cores       = 3
        ram_mb      = 11000
        mac_address = "BC:24:11:D0:83:10"
        ip_address  = "10.0.8.31"
      }
    },
    "nuc-g3p-2" : {
      "control" : {
        vm_id       = 7320
        cores       = 1
        ram_mb      = 3000
        mac_address = "BC:24:11:D0:73:20"
        ip_address  = "10.0.7.32"
      },
      "worker" : {
        vm_id       = 8320
        cores       = 3
        ram_mb      = 11000
        mac_address = "BC:24:11:D0:83:20"
        ip_address  = "10.0.8.32"
      }
    },
  }
}

module "talos-node" {
  source = "../modules/talos-node"

  for_each            = toset(data.proxmox_virtual_environment_nodes.nodes.names)
  proxmox_node_name   = each.value
  proxmox_storage_iso = var.proxmox_storage_iso
  talos = {
    version   = var.talos_version
    variant   = var.talos_variant
    arch      = var.talos_arch
    schematic = var.talos_schematic
  }
  vm_config = local.node_config[each.value]
}
