
locals {
  node_config = {
    "nuc-g2p-1" : {
      control_vm_id       = 7210
      control_cores       = 1
      control_ram         = 3000
      control_mac_address = "BC:24:11:D0:72:10"
      worker_vm_id        = 8210
      worker_cores        = 3
      worker_ram          = 7000
      worker_mac_address  = "BC:24:11:D0:82:10"
    },
    "nuc-g2p-2" : {
      control_vm_id       = 7220
      control_cores       = 1
      control_ram         = 3000
      control_mac_address = "BC:24:11:D0:72:20"
      worker_vm_id        = 8220
      worker_cores        = 3
      worker_ram          = 7000
      worker_mac_address  = "BC:24:11:D0:82:20"
    },
    "nuc-g3p-1" : {
      control_vm_id       = 7310
      control_cores       = 1
      control_ram         = 3000
      control_mac_address = "BC:24:11:D0:73:10"
      worker_vm_id        = 8310
      worker_cores        = 3
      worker_ram          = 11000
      worker_mac_address  = "BC:24:11:D0:83:10"
    },
    "nuc-g3p-2" : {
      control_vm_id       = 7320
      control_cores       = 1
      control_ram         = 3000
      control_mac_address = "BC:24:11:D0:73:20"
      worker_vm_id        = 8320
      worker_cores        = 3
      worker_ram          = 11000
      worker_mac_address  = "BC:24:11:D0:83:20"
    },
  }
}

module "talos-node" {
  source = "../modules/talos-node"

  for_each            = toset(data.proxmox_virtual_environment_nodes.nodes.names)
  proxmox_node_name   = each.value
  proxmox_storage_iso = var.proxmox_storage_iso
  talos_arch          = var.talos_arch
  talos_schematic     = var.talos_schematic
  talos_variant       = var.talos_variant
  talos_version       = var.talos_version
  control_vm_id       = local.node_config[each.value].control_vm_id
  control_cores       = local.node_config[each.value].control_cores
  control_ram         = local.node_config[each.value].control_ram
  control_mac_address = local.node_config[each.value].control_mac_address
  worker_vm_id        = local.node_config[each.value].worker_vm_id
  worker_cores        = local.node_config[each.value].worker_cores
  worker_ram          = local.node_config[each.value].worker_ram
  worker_mac_address  = local.node_config[each.value].worker_mac_address
}
