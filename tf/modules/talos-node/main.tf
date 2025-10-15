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

  url       = "https://factory.talos.dev/image/${var.talos.schematic}/v${var.talos.version}/${var.talos.variant}-${var.talos.arch}.iso"
  file_name = "talos-${var.talos.version}-${var.talos.variant}-${var.talos.arch}.iso"
  overwrite = false
}

locals {
  ctrl = var.vm_config["control"]
  wk   = var.vm_config["worker"]
}

module "control" {
  source = "../talos-vm"

  name        = "${local.ctrl.cluster_name}-cp-${var.proxmox_node_name}"
  description = "Control"
  node_name   = var.proxmox_node_name
  vm_id       = local.ctrl.vm_id
  num_cores   = local.ctrl.cores
  ram_mb      = local.ctrl.ram_mb
  mac_address = local.ctrl.mac_address
  iso_id      = proxmox_virtual_environment_download_file.talos_iso.id
  ip_address  = local.ctrl.ip_address
}

module "worker" {
  source = "../talos-vm"

  name        = "${local.wk.cluster_name}-wk-${var.proxmox_node_name}"
  description = "Worker"
  node_name   = var.proxmox_node_name
  vm_id       = local.wk.vm_id
  num_cores   = local.wk.cores
  ram_mb      = local.wk.ram_mb
  mac_address = local.wk.mac_address
  iso_id      = proxmox_virtual_environment_download_file.talos_iso.id
  ip_address  = local.wk.ip_address
}
