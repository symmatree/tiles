terraform {
  required_version = ">= 1.0"
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = ">= 0.9.0"
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
}

module "talos-node" {
  source              = "../talos-node"
  for_each            = toset(keys(var.node_config))
  cluster_name        = var.cluster_name
  proxmox_node_name   = each.value
  proxmox_storage_iso = var.proxmox_storage_iso
  talos               = var.talos
  vm_config           = var.node_config[each.value]
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
    yamlencode(local.cluster_config)
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
