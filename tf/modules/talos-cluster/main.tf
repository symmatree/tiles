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
  description = "Map of Proxmox nodes to their VMs configuration"
  type = map(object({
    control_planes = list(object({
      vm_id       = number
      cores       = number
      ram_mb      = number
      mac_address = string
      ip_address  = string
      name_suffix = optional(string, "")
    }))
    workers = list(object({
      vm_id       = number
      cores       = number
      ram_mb      = number
      mac_address = string
      ip_address  = string
      name_suffix = optional(string, "")
    }))
  }))
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


variable "apply_configs" {
  description = "Whether to apply Talos machine configuration"
  type        = bool
}

variable "onepassword_vault" {
  description = "1Password vault UUID."
  type        = string
}

# Load base configuration from YAML file
locals {
  base_config_yaml = file("${path.module}/talos-patch-all.yaml")
  base_config      = yamldecode(local.base_config_yaml)

  # Build control plane IPs list from all control plane VMs
  control_ips = [
    for vm in local.all_vms : vm.ip_address
    if vm.type == "control"
  ]

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

# Download Talos ISOs to each Proxmox node
module "talos-node" {
  source              = "../talos-node"
  for_each            = toset(keys(var.node_config))
  proxmox_node_name   = each.value
  proxmox_storage_iso = var.proxmox_storage_iso
  talos_configs       = [var.talos]
}

# Create a flat list of all VMs with their configurations
locals {
  all_vms = flatten([
    for node_name, node in var.node_config : concat(
      [
        for idx, cp in node.control_planes : {
          key            = "${node_name}-cp-${idx}"
          node_name      = node_name
          type           = "control"
          name           = "${var.cluster_name}-cp-${node_name}${cp.name_suffix}"
          vm_id          = cp.vm_id
          cores          = cp.cores
          ram_mb         = cp.ram_mb
          mac_address    = cp.mac_address
          ip_address     = cp.ip_address
          machine_config = data.talos_machine_configuration.machineconfig_cp.machine_configuration
        }
      ],
      [
        for idx, wk in node.workers : {
          key            = "${node_name}-wk-${idx}"
          node_name      = node_name
          type           = "worker"
          name           = "${var.cluster_name}-wk-${node_name}${wk.name_suffix}"
          vm_id          = wk.vm_id
          cores          = wk.cores
          ram_mb         = wk.ram_mb
          mac_address    = wk.mac_address
          ip_address     = wk.ip_address
          machine_config = data.talos_machine_configuration.machineconfig_worker.machine_configuration
        }
      ]
    )
  ])
  all_vms_map = { for vm in local.all_vms : vm.key => vm }

  # ISO key format
  iso_key = "${var.talos.version}-${var.talos.variant}-${var.talos.arch}"
}

# Create all VMs
module "talos-vm" {
  source   = "../talos-vm"
  for_each = local.all_vms_map

  name        = each.value.name
  description = each.value.type == "control" ? "Control" : "Worker"
  node_name   = each.value.node_name
  vm_id       = each.value.vm_id
  num_cores   = each.value.cores
  ram_mb      = each.value.ram_mb
  mac_address = each.value.mac_address
  iso_id      = module.talos-node[each.value.node_name].iso_ids[local.iso_key]
  ip_address  = each.value.ip_address
  started     = var.start_vms

  apply_config          = var.apply_configs
  client_configuration  = talos_machine_secrets.this.client_configuration
  machine_configuration = each.value.machine_config
}

resource "talos_machine_secrets" "this" {}

locals {
  machine_secrets = yamlencode(talos_machine_secrets.this.machine_secrets)
}

resource "onepassword_item" "machine_secrets" {
  count      = var.start_vms ? 1 : 0
  vault      = var.onepassword_vault
  title      = "${var.cluster_name}-machine-secrets"
  category   = "secure_note"
  note_value = local.machine_secrets
}


data "talos_client_configuration" "talosconfig" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = local.control_ips
}

resource "onepassword_item" "talosconfig" {
  count      = var.start_vms ? 1 : 0
  vault      = var.onepassword_vault
  title      = "${var.cluster_name}-talosconfig"
  category   = "secure_note"
  note_value = data.talos_client_configuration.talosconfig.talos_config
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

# Bootstrap setup
locals {
  # Bootstrap the first control plane node (alphabetically first by key)
  control_vms    = { for k, v in local.all_vms_map : k => v if v.type == "control" }
  bootstrap_node = local.control_vms[keys(local.control_vms)[0]].ip_address
}

variable "run_bootstrap" {
  description = "Whether to run the bootstrap process"
  type        = bool
  default     = false
}

# # Bootstrap the first control plane node (only if VMs are started)
resource "talos_machine_bootstrap" "this" {
  count = var.run_bootstrap ? 1 : 0

  node                 = local.bootstrap_node
  client_configuration = talos_machine_secrets.this.client_configuration

  depends_on = [
    module.talos-vm
  ]
}

resource "talos_cluster_kubeconfig" "this" {
  count = var.run_bootstrap ? 1 : 0
  depends_on = [
    talos_machine_bootstrap.this
  ]
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.bootstrap_node
}

resource "onepassword_item" "kubeconfig" {
  count      = var.run_bootstrap ? 1 : 0
  vault      = var.onepassword_vault
  title      = "${var.cluster_name}-kubeconfig"
  category   = "secure_note"
  note_value = resource.talos_cluster_kubeconfig.this[0].kubeconfig_raw
}

# Outputs
output "machine_secrets" {
  description = "Talos machine secrets"
  value       = local.machine_secrets
  sensitive   = true
}

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
  value       = var.start_vms ? local.bootstrap_node : null
}

output "cluster_endpoint" {
  description = "Cluster API endpoint"
  value       = "https://${var.control_plane_vip}:6443"
}

output "vms_started" {
  description = "Whether VMs are started and cluster is operational"
  value       = var.start_vms
}

output "all_vms" {
  description = "Map of all VMs in the cluster"
  value       = local.all_vms_map
}
