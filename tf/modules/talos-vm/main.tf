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
    unifi = {
      source  = "ubiquiti-community/unifi"
      version = ">= 0.41.3"
    }
  }
}

resource "proxmox_virtual_environment_vm" "main" {
  acpi          = true
  bios          = "seabios"
  description   = "${var.description} - ${var.vm_id} - ${var.name} - ${var.ip_address}"
  name          = var.name
  node_name     = var.node_name
  on_boot       = null
  pool_id       = null
  scsi_hardware = "virtio-scsi-single"
  started       = false
  tags          = []
  vm_id         = var.vm_id
  agent {
    enabled = true
    timeout = "15m"
    trim    = false
  }
  cpu {
    cores = var.num_cores
    type  = "x86-64-v3"
  }
  cdrom {
    file_id   = var.iso_id
    interface = "ide2"
  }
  disk {
    backup            = true
    cache             = "none"
    file_format       = "raw"
    interface         = "scsi0"
    iothread          = true
    path_in_datastore = "vm-${var.vm_id}-disk-0"
    size              = var.disk_size_gb
    ssd               = false
  }
  memory {
    dedicated = var.ram_mb
    floating  = var.ram_mb
  }
  network_device {
    bridge      = "vmbr0"
    firewall    = true
    mac_address = var.mac_address
    # mtu=1 means use bridge MTU
    mtu    = 1
    queues = 16
  }
  operating_system {
    type = "l26"
  }
}

resource "unifi_user" "vm_client" {
  mac              = var.mac_address
  name             = var.name
  note             = "${var.description} - ${var.vm_id} - ${var.name}"
  fixed_ip         = var.ip_address
  local_dns_record = "${var.name}.${var.domain_name}"
}
