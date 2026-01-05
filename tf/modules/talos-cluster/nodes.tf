
# Load base configuration from YAML file
locals {
  config_path             = "${path.module}/talos-config.yaml"
  base_config_yaml        = file(local.config_path)
  vm_install_image        = "factory.talos.dev/installer/${var.talos_vm_schematic}:v${var.talos_version}"
  metal_amd_install_image = "factory.talos.dev/installer/${var.talos_metal_amd_schematic}:v${var.talos_version}"

  common_patch_yaml = yamlencode({
    "version" = "v1alpha1"
    "cluster" = {
      "clusterName" = var.cluster_name
      "network" = {
        "podSubnets"     = [var.pod_cidr]
        "serviceSubnets" = [var.service_cidr]
      }
    }
  })

  # See: https://docs.siderolabs.com/talos/v1.12/reference/configuration/network/layer2vipconfig
  layer2_vip_patch_yaml = yamlencode({
    apiVersion = "v1alpha1"
    kind       = "Layer2VIPConfig"
    name       = var.control_plane_vip
    link       = var.control_plane_vip_link
  })
}

output "config_path" {
  description = "Path to the base configuration file"
  value       = local.config_path
}

# Create all VMs
module "talos-vm" {
  source   = "../talos-vm"
  for_each = var.vms

  name                 = each.key
  description          = each.value.type == "control" ? "Control" : "Worker"
  node_name            = each.value.proxmox_node_name
  vm_id                = each.value.vm_id
  num_cores            = each.value.cores
  ram_mb               = each.value.ram_mb
  mac_address          = each.value.mac_address
  iso_id               = var.nodes_to_iso_ids[each.value.proxmox_node_name]
  ip_address           = each.value.ip_address
  client_configuration = talos_machine_secrets.this.client_configuration
  machine_configuration = (each.value.type == "control" ?
    data.talos_machine_configuration.machineconfig_cp.machine_configuration
  : data.talos_machine_configuration.machineconfig_worker.machine_configuration)

  # Patches to apply via talos_machine_configuration_apply
  # Common patch for all nodes (equivalent to common-patch.yaml.tmpl)
  # Install image patch for all nodes
  # Layer2 VIP patch only for control plane nodes (equivalent to layer2-vip-config.yaml.tmpl)
  config_patches = concat(
    [local.base_config_yaml],
    [local.common_patch_yaml],
    [yamlencode({
      "machine" = {
        "install" = { "image" = local.vm_install_image }
      }
    })],
    each.value.type == "control" ? [local.layer2_vip_patch_yaml] : []
  )
}

module "talos-amd-metal" {
  source   = "../talos-metal"
  for_each = var.metal_amd_nodes

  name                 = each.value.name
  mac_address          = each.value.mac_address
  ip_address           = each.value.ip_address
  client_configuration = talos_machine_secrets.this.client_configuration
  machine_configuration = (each.value.type == "control" ?
    data.talos_machine_configuration.machineconfig_cp.machine_configuration
  : data.talos_machine_configuration.machineconfig_worker.machine_configuration)

  config_patches = concat(
    [local.base_config_yaml],
    [local.common_patch_yaml],
    [yamlencode({
      "machine" = {
        "install" = { "image" = local.metal_amd_install_image }
      }
    })],
    each.value.type == "control" ? [local.layer2_vip_patch_yaml] : []
  )
}
