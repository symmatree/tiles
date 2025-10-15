
locals {
  tiles_prod = {
    "nuc-g2p-1" : {
      "control" : {
        vm_id        = 7210
        cores        = 1
        ram_mb       = 3000
        mac_address  = "BC:24:11:D0:72:10"
        ip_address   = "10.0.7.21"
        cluster_name = "tiles"
      },
      "worker" : {
        vm_id        = 8210
        cores        = 3
        ram_mb       = 7000
        mac_address  = "BC:24:11:D0:82:10"
        ip_address   = "10.0.8.21"
        cluster_name = "tiles"
      }
    },
    "nuc-g2p-2" : {
      "control" : {
        vm_id        = 7220
        cores        = 1
        ram_mb       = 3000
        mac_address  = "BC:24:11:D0:72:20"
        ip_address   = "10.0.7.22"
        cluster_name = "tiles"
      },
      "worker" : {
        vm_id        = 8220
        cores        = 3
        ram_mb       = 7000
        mac_address  = "BC:24:11:D0:82:20"
        ip_address   = "10.0.8.22"
        cluster_name = "tiles"
      }
    },
    "nuc-g3p-1" : {
      "control" : {
        vm_id        = 7310
        cores        = 1
        ram_mb       = 3000
        mac_address  = "BC:24:11:D0:73:10"
        ip_address   = "10.0.7.31"
        cluster_name = "tiles"
      },
      "worker" : {
        vm_id        = 8310
        cores        = 3
        ram_mb       = 11000
        mac_address  = "BC:24:11:D0:83:10"
        ip_address   = "10.0.8.31"
        cluster_name = "tiles"
      }
    },
  }
}

module "talos-node" {
  source = "../modules/talos-node"

  for_each            = toset(keys(local.tiles_prod))
  proxmox_node_name   = each.value
  proxmox_storage_iso = var.proxmox_storage_iso
  talos = {
    version   = var.talos_version
    variant   = var.talos_variant
    arch      = var.talos_arch
    schematic = var.talos_schematic
  }
  vm_config = local.tiles_prod[each.value]
}
