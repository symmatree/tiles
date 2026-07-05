
# Load base configuration from YAML file
locals {
  config_path               = "${path.module}/talos-config.yaml"
  base_config_yaml          = file(local.config_path)
  vm_install_image          = "factory.talos.dev/installer/${var.talos_vm_schematic}:v${var.talos_version}"
  metal_amd_install_image   = "factory.talos.dev/metal-installer/${var.talos_metal_amd_schematic}:v${var.talos_version}"
  metal_intel_install_image = "factory.talos.dev/metal-installer/${var.talos_metal_intel_schematic}:v${var.talos_version}"

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

  # Widen the within-node OOM safety margin: raise the kubelet hard-eviction
  # threshold so the kubelet reclaims (evicts low-priority pods) before the
  # kernel OOM-killer fires. Re-declares the default nodefs/imagefs thresholds
  # so the extraConfig merge does not drop disk-pressure eviction. Empty list
  # (no patch) when the knob is unset -- e.g. the test cluster keeps defaults.
  eviction_patches = var.kubelet_eviction_memory_available == null ? [] : [yamlencode({
    machine = {
      kubelet = {
        extraConfig = {
          evictionHard = {
            "memory.available"  = var.kubelet_eviction_memory_available
            "nodefs.available"  = "10%"
            "nodefs.inodesFree" = "5%"
            "imagefs.available" = "15%"
          }
        }
      }
    }
  })]
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
  unifi_network_id     = var.unifi_network_id
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
  # taint as specified
  config_patches = concat(
    [local.base_config_yaml],
    [local.common_patch_yaml],
    local.eviction_patches,
    [yamlencode({
      "machine" = {
        "install" = { "image" = local.vm_install_image }
      }
    })],
    each.value.type == "control" ? [local.layer2_vip_patch_yaml] : [],
    each.value.taint != "" ? [yamlencode({
      "machine" = {
        "kubelet" = {
          "extraArgs" = {
            "register-with-taints" = "dedicated=${each.value.taint}:NoSchedule"
          }
        }
      }
    })] : []
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

  unifi_network_id = var.unifi_network_id
  config_patches = concat(
    [local.base_config_yaml],
    [local.common_patch_yaml],
    local.eviction_patches,
    [yamlencode({
      "machine" = {
        "install" = { "image" = local.metal_amd_install_image }
      }
    })],
    each.value.type == "control" ? [local.layer2_vip_patch_yaml] : [],
    each.value.taint != "" ? [yamlencode({
      "machine" = {
        "kubelet" = {
          "extraArgs" = {
            "register-with-taints" = "dedicated=${each.value.taint}:${each.value.taint_effect}"
          }
        }
      }
    })] : [],
    each.value.machine_config_patches
  )

  apply_mode = var.metal_apply_mode

  # Order the metal (re)apply after the etcd bootstrap so an apply_mode="reboot"
  # rebuild reboots the node into the *new* cluster rather than the old one.
  depends_on = [talos_machine_bootstrap.this]
}

module "talos-intel-metal" {
  source   = "../talos-metal"
  for_each = var.metal_intel_nodes

  name                 = each.value.name
  mac_address          = each.value.mac_address
  ip_address           = each.value.ip_address
  client_configuration = talos_machine_secrets.this.client_configuration
  machine_configuration = (each.value.type == "control" ?
    data.talos_machine_configuration.machineconfig_cp.machine_configuration
  : data.talos_machine_configuration.machineconfig_worker.machine_configuration)

  unifi_network_id = var.unifi_network_id
  config_patches = concat(
    [local.base_config_yaml],
    [local.common_patch_yaml],
    local.eviction_patches,
    [yamlencode({
      "machine" = {
        "install" = { "image" = local.metal_intel_install_image }
      }
    })],
    each.value.type == "control" ? [local.layer2_vip_patch_yaml] : [],
    each.value.taint != "" ? [yamlencode({
      "machine" = {
        "kubelet" = {
          "extraArgs" = {
            "register-with-taints" = "dedicated=${each.value.taint}:${each.value.taint_effect}"
          }
        }
      }
    })] : [],
    each.value.machine_config_patches
  )

  apply_mode = var.metal_apply_mode

  # Order the metal (re)apply after the etcd bootstrap so an apply_mode="reboot"
  # rebuild reboots the node into the *new* cluster rather than the old one.
  depends_on = [talos_machine_bootstrap.this]
}
