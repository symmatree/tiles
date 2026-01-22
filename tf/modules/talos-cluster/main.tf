resource "talos_machine_secrets" "this" {}

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

variable "cluster_nfs_path" {
  description = "NFS path for the cluster's shared NFS storage"
  type        = string
}

variable "datasets_nfs_path" {
  description = "NFS export path for the datasets share"
  type        = string
}

variable "nfs_server" {
  description = "NFS server hostname or IP address"
  type        = string
}

variable "seed_project_id" {
  description = "GCP seed project ID (symm-custodes) where shared DNS zones are located"
  type        = string
}

variable "dns_zone_ad_local" {
  description = "DNS zone name for ad.local.symmatree.com in seed project"
  type        = string
}

variable "dns_zone_local" {
  description = "DNS zone name for local.symmatree.com in seed project"
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
  seed_project_id   = var.seed_project_id
  dns_zone_ad_local = var.dns_zone_ad_local
  dns_zone_local    = var.dns_zone_local
}

resource "onepassword_item" "misc_config" {
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
      value = var.cluster_name == "tiles" ? "prod" : "test"
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
      label = "seed_project_id"
      value = var.seed_project_id
    }
    field {
      label = "cluster_nfs_path"
      value = var.cluster_nfs_path
    }
    field {
      label = "datasets_nfs_path"
      value = var.datasets_nfs_path
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
      label = "talos_vm_install_image"
      value = local.vm_install_image
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
  # Keep data source minimal - patches go in talos_machine_configuration_apply
}

data "talos_machine_configuration" "machineconfig_worker" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.control_plane_vip}:6443"
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  # Keep data source minimal - patches go in talos_machine_configuration_apply
}

# # Bootstrap the first control plane node (only if VMs are started)
resource "talos_machine_bootstrap" "this" {
  node                 = local.bootstrap_ip
  client_configuration = talos_machine_secrets.this.client_configuration

  depends_on = [
    module.talos-vm
  ]
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [
    talos_machine_bootstrap.this
  ]
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.bootstrap_ip
}

resource "onepassword_item" "kubeconfig" {
  vault      = var.onepassword_vault
  title      = "${var.cluster_name}-kubeconfig"
  category   = "secure_note"
  note_value = resource.talos_cluster_kubeconfig.this.kubeconfig_raw

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

output "control_plane_vip" {
  description = "Control plane VIP"
  value       = var.control_plane_vip
}
