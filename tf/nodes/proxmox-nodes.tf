locals {
  all_node_names = setunion(
    [for _, v in local.test_vms : v.proxmox_node_name],
    [for _, v in local.prod_vms : v.proxmox_node_name]
  )
}

# Download Talos ISOs to each Proxmox node
module "talos-node" {
  source = "../modules/talos-node"
  # for_each            = toset(data.proxmox_virtual_environment_nodes.nodes.names)
  for_each            = local.all_node_names
  proxmox_node_name   = each.value
  proxmox_storage_iso = var.proxmox_storage_iso
  talos_configs       = local.talos_configs
}

locals {
  nodes_to_iso_ids = {
    for node_name in data.proxmox_virtual_environment_nodes.nodes.names : node_name =>
    module.talos-node[node_name].iso_ids
  }
}
