
locals {
  tiles_test = {
    "nuc-g3p-2" : {
      "control" : {
        cluster_name = "tiles-test"
        vm_id        = 7320
        cores        = 1
        ram_mb       = 3000
        mac_address  = "BC:24:11:D0:73:20"
        ip_address   = "10.0.7.32"
      },
      "worker" : {
        cluster_name = "tiles-test"
        vm_id        = 8320
        cores        = 3
        ram_mb       = 11000
        mac_address  = "BC:24:11:D0:83:20"
        ip_address   = "10.0.8.32"
      }
    },
  }
}

module "tiles-test-node" {
  source = "../modules/talos-node"

  for_each            = toset(keys(local.tiles_test))
  proxmox_node_name   = each.value
  proxmox_storage_iso = var.proxmox_storage_iso
  talos = {
    version   = var.talos_version
    variant   = var.talos_variant
    arch      = var.talos_arch
    schematic = var.talos_schematic
  }
  vm_config = local.tiles_test[each.value]
}
