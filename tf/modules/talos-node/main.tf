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
}

data "terraform_remote_state" "bootstrap" {
  backend = "gcs"
  config = {
    bucket = "custodes-tf-state"
    prefix = "terraform/tiles/bootstrap"
  }
}

# Upload Talos ISO to Proxmox
resource "proxmox_virtual_environment_download_file" "talos_iso" {
  content_type = "iso"
  datastore_id = var.proxmox_storage_iso
  node_name    = var.proxmox_node_name

  url       = "https://factory.talos.dev/image/${var.talos_schematic}/v${var.talos_version}/${var.talos_variant}-${var.talos_arch}.iso"
  file_name = "talos-${var.talos_version}-${var.talos_variant}-${var.talos_arch}.iso"
  overwrite = false
}

module "control" {
  source = "../talos-vm"

  name        = "{{var.proxmox_node_name}}-tiles-cp"
  description = "Control Plane {{var.proxmox_node_name}}"
  node_name   = var.proxmox_node_name
  vm_id       = var.control_vm_id
  num_cores   = var.control_cores
  ram_mb      = var.control_ram
  mac_address = var.control_mac_address
  iso_id      = proxmox_virtual_environment_download_file.talos_iso.id
}

module "worker" {
  source = "../talos-vm"

  name        = "{{var.proxmox_node_name}}-tiles-wk"
  description = "Worker Node {{var.proxmox_node_name}}"
  node_name   = var.proxmox_node_name
  vm_id       = var.worker_vm_id
  num_cores   = var.worker_cores
  ram_mb      = var.worker_ram
  mac_address = var.worker_mac_address
  iso_id      = proxmox_virtual_environment_download_file.talos_iso.id
}
