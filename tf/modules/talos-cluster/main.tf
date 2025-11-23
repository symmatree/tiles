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

variable "nodes_to_iso_ids" {
  description = "Map of Proxmox nodes to their Talos ISO IDs"
  type        = map(string)
}

variable "vms" {
  description = "List of VMs in the cluster"
  type = map(object({
    type              = string # "control" or "worker"
    proxmox_node_name = string
    vm_id             = number
    cores             = number
    ram_mb            = number
    mac_address       = string
    ip_address        = string
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

variable "external_ip_cidr" {
  description = "External IP CIDR for the cluster"
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
  base_config_yaml = file("${path.module}/talos-config.yaml")

  install_image = "factory.talos.dev/installer/${var.talos.schematic}:v${var.talos.version}"
  common_patch = {
    cluster = {
      clusterName = var.cluster_name
      network = {
        podSubnets     = [var.pod_cidr]
        serviceSubnets = [var.service_cidr]
      }
    }
    machine = {
      install = { image = local.install_image }
    }
  }

  # Control plane specific configuration with VIP
  control_plane_patch = {
    machine = {
      network = {
        interfaces = [{
          deviceSelector = { physical = true }
          dhcp           = true
          vip            = { ip = var.control_plane_vip }
        }]
      }
    }
  }
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
  started              = var.start_vms
  apply_config         = var.apply_configs
  client_configuration = talos_machine_secrets.this.client_configuration
  machine_configuration = (each.value.type == "control" ?
    data.talos_machine_configuration.machineconfig_cp.machine_configuration
  : data.talos_machine_configuration.machineconfig_worker.machine_configuration)
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
  section {
    label = "metadata"
    field {
      label = "source"
      value = "managed by terraform"
    }
    field {
      label = "root_module"
      value = basename(abspath(path.root))
    }
    field {
      label = "module"
      value = basename(abspath(path.module))
    }
  }
}

locals {
  control_ips  = [for _, vm in var.vms : vm.ip_address if vm.type == "control"]
  bootstrap_ip = local.control_ips[0]
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
  section {
    label = "metadata"
    field {
      label = "source"
      value = "managed by terraform"
    }
    field {
      label = "root_module"
      value = basename(abspath(path.root))
    }
    field {
      label = "module"
      value = basename(abspath(path.module))
    }
  }
}

resource "onepassword_item" "misc_config" {
  count    = var.start_vms ? 1 : 0
  vault    = var.onepassword_vault
  title    = "${var.cluster_name}-misc-config"
  category = "secure_note"
  section {
    label = "config"
    field {
      label = "pod_cidr"
      value = var.pod_cidr
    }
    field {
      label = "targetRevision"
      value = "main"
    }
    field {
      label = "cluster_name"
      value = var.cluster_name
    }
    field {
      label = "external_ip_cidr"
      value = var.external_ip_cidr
    }
    field {
      label = "vault_name"
      value = var.onepassword_vault
    }
  }
  section {
    label = "metadata"
    field {
      label = "source"
      value = "managed by terraform"
    }
    field {
      label = "root_module"
      value = basename(abspath(path.root))
    }
    field {
      label = "module"
      value = basename(abspath(path.module))
    }
  }
}

data "talos_machine_configuration" "machineconfig_cp" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.control_plane_vip}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  config_patches = [
    local.base_config_yaml,
    yamlencode(local.common_patch),
    yamlencode(local.control_plane_patch)
  ]
}

data "talos_machine_configuration" "machineconfig_worker" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.control_plane_vip}:6443"
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  config_patches = [
    local.base_config_yaml,
    yamlencode(local.common_patch)
  ]
}

variable "run_bootstrap" {
  description = "Whether to run the bootstrap process"
  type        = bool
  default     = false
}

# # Bootstrap the first control plane node (only if VMs are started)
resource "talos_machine_bootstrap" "this" {
  count = var.run_bootstrap ? 1 : 0

  node                 = local.bootstrap_ip
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
  node                 = local.bootstrap_ip
}

resource "onepassword_item" "kubeconfig" {
  count      = var.run_bootstrap ? 1 : 0
  vault      = var.onepassword_vault
  title      = "${var.cluster_name}-kubeconfig"
  category   = "secure_note"
  note_value = resource.talos_cluster_kubeconfig.this[0].kubeconfig_raw

  section {
    label = "metadata"
    field {
      label = "source"
      value = "managed by terraform"
    }
    field {
      label = "root_module"
      value = basename(abspath(path.root))
    }
    field {
      label = "module"
      value = basename(abspath(path.module))
    }
  }
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
  value       = var.start_vms ? local.bootstrap_ip : null
}

output "cluster_endpoint" {
  description = "Cluster API endpoint"
  value       = "https://${var.control_plane_vip}:6443"
}

output "vms_started" {
  description = "Whether VMs are started and cluster is operational"
  value       = var.start_vms
}
