terraform {
  required_version = ">= 1.0"
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = ">= 0.9.0"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.84"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = ">= 2.1.2"
    }
  }
}

variable "node_config" {
  description = "Node names to control/worker to config"
  type = map(map(object({
    vm_id       = number
    cores       = number
    ram_mb      = number
    mac_address = string
    ip_address  = string
  })))
}

variable "cluster_name" {
  description = "Talos cluster name"
  type        = string
}

variable "proxmox_storage_iso" {
  description = "Proxmox storage for ISO files"
  type        = string
}

variable "talos" {
  description = "Talos configuration"
  type = object({
    version   = string
    variant   = string
    arch      = string
    schematic = string
  })
}

variable "pod_cidr" {
  description = "Pod CIDR for the cluster"
  type        = string
}

variable "service_cidr" {
  description = "Service CIDR for the cluster"
  type        = string
}

variable "control_plane_vip" {
  description = "Control plane VIP for the cluster"
  type        = string
}

variable "start_vms" {
  description = "Whether to start the VMs after creation"
  type        = bool
  default     = false
}

# Load base configuration from YAML file
locals {
  base_config_yaml = file("${path.module}/talos-patch-all.yaml")
  base_config      = yamldecode(local.base_config_yaml)

  # Build control plane IPs list
  control_ips = [for node_name in keys(var.node_config) : var.node_config[node_name]["control"].ip_address]

  # Override configuration with cluster-specific values
  cluster_config = merge(local.base_config, {
    cluster = merge(local.base_config.cluster, {
      clusterName = var.cluster_name
      network = merge(local.base_config.cluster.network, {
        podSubnets     = [var.pod_cidr]
        serviceSubnets = [var.service_cidr]
      })
    })
    machine = merge(local.base_config.machine, {
      install = merge(local.base_config.machine.install, {
        image = "factory.talos.dev/installer/${var.talos.schematic}:v${var.talos.version}"
      })
    })
  })

  # Control plane specific configuration with VIP
  control_plane_config = merge(local.cluster_config, {
    machine = merge(local.cluster_config.machine, {
      network = {
        interfaces = [
          {
            deviceSelector = {
              physical = true
            }
            vip = {
              ip = var.control_plane_vip
            }
          }
        ]
      }
    })
  })
}

module "talos-node" {
  source              = "../talos-node"
  for_each            = toset(keys(var.node_config))
  cluster_name        = var.cluster_name
  proxmox_node_name   = each.value
  proxmox_storage_iso = var.proxmox_storage_iso
  talos               = var.talos
  vm_config           = var.node_config[each.value]
  start_vms           = var.start_vms
}

resource "talos_machine_secrets" "this" {}

data "talos_client_configuration" "talosconfig" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = local.control_ips
}

data "talos_machine_configuration" "machineconfig_cp" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.control_plane_vip}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  config_patches = [
    yamlencode(local.control_plane_config)
  ]
}

data "talos_machine_configuration" "machineconfig_worker" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.control_plane_vip}:6443"
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  config_patches = [
    yamlencode(local.cluster_config)
  ]
}

# Start VMs and apply Talos configurations
locals {
  # Flatten node configurations for easier iteration
  all_nodes = flatten([
    for node_name, node_config in var.node_config : [
      {
        key        = "${node_name}-control"
        node_name  = node_name
        type       = "control"
        ip_address = node_config.control.ip_address
        vm_id      = node_config.control.vm_id
      },
      {
        key        = "${node_name}-worker"
        node_name  = node_name
        type       = "worker"
        ip_address = node_config.worker.ip_address
        vm_id      = node_config.worker.vm_id
      }
    ]
  ])
  all_nodes_map = { for node in local.all_nodes : node.key => node }
}

# Apply Talos configuration to control plane nodes (only if VMs are started)
resource "talos_machine_configuration_apply" "control_plane" {
  for_each = var.start_vms ? {
    for k, v in local.all_nodes_map : k => v
    if v.type == "control"
  } : {}

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.machineconfig_cp.machine_configuration
  node                        = each.value.ip_address

  depends_on = [module.talos-node]
}

# Apply Talos configuration to worker nodes (only if VMs are started)
resource "talos_machine_configuration_apply" "worker" {
  for_each = var.start_vms ? {
    for k, v in local.all_nodes_map : k => v
    if v.type == "worker"
  } : {}

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.machineconfig_worker.machine_configuration
  node                        = each.value.ip_address

  depends_on = [module.talos-node]
}

# Bootstrap the first control plane node (only if VMs are started)
resource "talos_machine_bootstrap" "this" {
  count = var.start_vms ? 1 : 0

  # Bootstrap the first control plane node (alphabetically first by key)
  node                 = local.all_nodes_map[keys({ for k, v in local.all_nodes_map : k => v if v.type == "control" })[0]].ip_address
  client_configuration = talos_machine_secrets.this.client_configuration

  depends_on = [
    talos_machine_configuration_apply.control_plane
  ]
}

# Outputs
output "talosconfig" {
  description = "Talos client configuration"
  value       = data.talos_client_configuration.talosconfig.talos_config
  sensitive   = true
}

output "control_plane_config" {
  description = "Control plane machine configuration"
  value       = data.talos_machine_configuration.machineconfig_cp.machine_configuration
  sensitive   = true
}

output "worker_config" {
  description = "Worker machine configuration"
  value       = data.talos_machine_configuration.machineconfig_worker.machine_configuration
  sensitive   = true
}

output "cluster_name" {
  description = "Cluster name"
  value       = var.cluster_name
}

output "control_plane_ips" {
  description = "Control plane IP addresses"
  value       = local.control_ips
}

output "control_plane_vip" {
  description = "Control plane VIP"
  value       = var.control_plane_vip
}

output "bootstrap_node" {
  description = "Node that was bootstrapped (only when VMs are started)"
  value       = var.start_vms ? local.all_nodes_map[keys({ for k, v in local.all_nodes_map : k => v if v.type == "control" })[0]].ip_address : null
}

output "cluster_endpoint" {
  description = "Cluster API endpoint"
  value       = "https://${var.control_plane_vip}:6443"
}

output "vms_started" {
  description = "Whether VMs are started and cluster is operational"
  value       = var.start_vms
}
