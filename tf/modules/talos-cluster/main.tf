
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

variable "control_plane_vip_link" {
  description = "Network interface name for the control plane VIP (e.g., 'ens18' for virtio-net). Required for Talos v1.12+ which uses Layer2VIPConfig."
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

variable "onepassword_vault_name" {
  description = "1Password vault name (e.g., 'tiles-secrets')."
  type        = string
}

variable "admin_user" {
  description = "Admin user email"
  type        = string
}

# Load base configuration from YAML file
locals {
  config_path       = "${path.module}/talos-config.yaml"
  base_config_yaml  = file(local.config_path)
  layer2_vip_config = file("${path.module}/tiles-test-layer2-vip.yaml")
  install_image     = "factory.talos.dev/installer/${var.talos.schematic}:v${var.talos.version}"
  common_patch = {
    "version" = "v1alpha1"
    "cluster" = {
      "clusterName" = var.cluster_name
      "network" = {
        "podSubnets"     = [var.pod_cidr]
        "serviceSubnets" = [var.service_cidr]
      }
    }
    "machine" = {
      "install" = { "image" = local.install_image }
    }
  }

  # Control plane specific configuration
  # Note: VIP configuration is handled separately via Layer2VIPConfig (multi-document style)
  # The old machine.network.interfaces[].vip syntax was removed in Talos v1.12
  # control_plane_patch = {
  #   version = "v1alpha1"
  #   machine = {
  #     network = {
  #       interfaces = [{
  #         deviceSelector = { physical = true }
  #         dhcp           = true
  #       }]
  #     }
  #   }
  # }

  # Layer2VIPConfig document (multi-document style)
  # See: https://docs.siderolabs.com/talos/v1.12/reference/configuration/network/layer2vipconfig
  # Encode as JSON (starts with '{') to avoid provider thinking it's a filename
  # The provider's LoadPatches checks: if no newlines/spaces and doesn't start with '[' or '{', assume filename
  layer2_vip_config2 = yamlencode({
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

variable "main_project_id" {
  description = "GCP project for this cluster"
  type        = string
}

variable "kms_project_id" {
  description = "Google Cloud KMS project ID"
  type        = string
}

variable "gcp_region" {
  description = "Google Cloud region"
  type        = string
}

variable "loki_nfs_path" {
  description = "NFS path for Loki storage"
  type        = string
}

variable "mimir_nfs_path" {
  description = "NFS path for Mimir storage"
  type        = string
}

variable "loki_nfs_uid" {
  description = "UID of the NAS user account for Loki NFS access"
  type        = number
}

variable "mimir_nfs_uid" {
  description = "UID of the NAS user account for Mimir NFS access"
  type        = number
}

variable "nfs_server" {
  description = "NFS server hostname or IP address"
  type        = string
}

module "k8s" {
  source            = "../k8s-cluster"
  main_project_id   = var.main_project_id
  kms_project_id    = var.kms_project_id
  gcp_region        = var.gcp_region
  cluster_name      = var.cluster_name
  onepassword_vault = var.onepassword_vault
  admin_user        = var.admin_user
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
      value = var.onepassword_vault_name
    }
    field {
      label = "project_id"
      value = var.main_project_id
    }
    field {
      label = "loki_nfs_path"
      value = var.loki_nfs_path
    }
    field {
      label = "mimir_nfs_path"
      value = var.mimir_nfs_path
    }
    field {
      label = "loki_nfs_uid"
      value = tostring(var.loki_nfs_uid)
    }
    field {
      label = "mimir_nfs_uid"
      value = tostring(var.mimir_nfs_uid)
    }
    field {
      label = "nfs_server"
      value = var.nfs_server
    }
    field {
      label = "service_cidr"
      value = var.service_cidr
    }
    field {
      label = "control_plane_vip"
      value = var.control_plane_vip
    }
    field {
      label = "control_plane_vip_link"
      value = var.control_plane_vip_link
    }
    field {
      label = "talos_install_image"
      value = local.install_image
    }
    field {
      label = "control_plane_ips"
      value = join(",", local.control_ips)
    }
    field {
      label = "bootstrap_ip"
      value = local.bootstrap_ip
    }
    field {
      label = "worker_ips"
      value = join(",", [for _, vm in var.vms : vm.ip_address if vm.type == "worker"])
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
    local.layer2_vip_config,
    # jsonencode(local.common_patch),
  ]
}

data "talos_machine_configuration" "machineconfig_worker" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.control_plane_vip}:6443"
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  config_patches = [
    local.base_config_yaml,
    # jsonencode(local.common_patch)
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
