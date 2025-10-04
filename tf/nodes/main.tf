terraform {
  required_version = ">= 1.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.84"
    }
    google = {
      source  = "hashicorp/google"
      version = ">= 7.0"
    }
  }
  backend "gcs" {
    bucket = "custodes-tf-state"
    prefix = "terraform/tiles/nodes"
  }
}

data "terraform_remote_state" "bootstrap" {
  backend = "gcs"
  config = {
    bucket = "custodes-tf-state"
    prefix = "terraform/tiles/bootstrap"
  }
}

locals {
  proxmox_tiles_tf_user_id = data.terraform_remote_state.bootstrap.outputs.proxmox_tiles_tf_user_id
  proxmox_tiles_tf_token_id    = data.terraform_remote_state.bootstrap.outputs.proxmox_tiles_tf_token_id
  proxmox_tiles_tf_token_value = data.terraform_remote_state.bootstrap.outputs.proxmox_tiles_tf_token_value
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  api_token = "${local.proxmox_tiles_tf_user_id}!provider=${local.proxmox_tiles_tf_token_value}"
  insecure = true
}

# Upload Talos ISO to Proxmox
resource "proxmox_virtual_environment_download_file" "talos_iso" {
  content_type = "iso"
  datastore_id = var.proxmox_storage_iso
  node_name    = var.proxmox_node_name
  
  url = "https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v${var.talos_version}/metal-amd64.iso"
  file_name = "talos-${var.talos_version}-amd64.iso"
  
  # Only download if file doesn't exist
  overwrite = false
}

# # Control plane VMs
# resource "proxmox_virtual_environment_vm" "talos_control" {
#   count = var.control_plane_count
  
#   name        = "${var.cluster_name}-control-${count.index + 1}"
#   description = "Talos Linux Control Plane Node ${count.index + 1}"
#   node_name   = var.proxmox_node_name
#   vm_id       = var.control_plane_vm_id_start + count.index

#   agent {
#     enabled = true
#   }

#   cpu {
#     cores = var.control_plane_cpu_cores
#     type  = "host"
#   }

#   memory {
#     dedicated = var.control_plane_memory_mb
#   }

#   network_device {
#     bridge      = var.proxmox_network_bridge
#     mac_address = var.control_plane_mac_addresses[count.index]
#   }

#   disk {
#     datastore_id = var.proxmox_storage_vm
#     file_id      = proxmox_virtual_environment_download_file.talos_iso.id
#     interface    = "ide0"
#     size         = 4
#   }

#   disk {
#     datastore_id = var.proxmox_storage_vm
#     file_format  = "raw"
#     interface    = "scsi0"
#     iothread     = true
#     ssd          = true
#     size         = var.control_plane_disk_size_gb
#   }

#   boot_order = ["ide0", "scsi0"]

#   operating_system {
#     type = "l26"
#   }

#   serial_device {
#     device = "socket"
#   }

#   vga {
#     enabled = true
#     type    = "serial0"
#   }

#   initialization {
#     dns {
#       servers = var.dns_servers
#     }
    
#     ip_config {
#       ipv4 {
#         address = "${var.control_plane_ips[count.index]}/${var.network_cidr_bits}"
#         gateway = var.network_gateway
#       }
#     }
#   }

#   lifecycle {
#     ignore_changes = [
#       boot_order,
#       disk[0].file_id,
#     ]
#   }
# }

# # Worker VMs
# resource "proxmox_virtual_environment_vm" "talos_worker" {
#   count = var.worker_count
  
#   name        = "${var.cluster_name}-worker-${count.index + 1}"
#   description = "Talos Linux Worker Node ${count.index + 1}"
#   node_name   = var.proxmox_node_name
#   vm_id       = var.worker_vm_id_start + count.index

#   agent {
#     enabled = true
#   }

#   cpu {
#     cores = var.worker_cpu_cores
#     type  = "host"
#   }

#   memory {
#     dedicated = var.worker_memory_mb
#   }

#   network_device {
#     bridge      = var.proxmox_network_bridge
#     mac_address = var.worker_mac_addresses[count.index]
#   }

#   disk {
#     datastore_id = proxmox_virtual_environment_download_file.talos_iso.datastore_id
#     file_id      = proxmox_virtual_environment_download_file.talos_iso.id
#     interface    = "ide0"
#     size         = 4
#   }

#   disk {
#     datastore_id = var.proxmox_storage_vm
#     file_format  = "raw"
#     interface    = "scsi0"
#     iothread     = true
#     ssd          = true
#     size         = var.worker_disk_size_gb
#   }

#   boot_order = ["ide0", "scsi0"]

#   operating_system {
#     type = "l26"
#   }

#   serial_device {
#     device = "socket"
#   }

#   vga {
#     enabled = true
#     type    = "serial0"
#   }

#   initialization {
#     dns {
#       servers = var.dns_servers
#     }
    
#     ip_config {
#       ipv4 {
#         address = "${var.worker_ips[count.index]}/${var.network_cidr_bits}"
#         gateway = var.network_gateway
#       }
#     }
#   }

#   lifecycle {
#     ignore_changes = [
#       boot_order,
#       disk[0].file_id,
#     ]
#   }
# }
