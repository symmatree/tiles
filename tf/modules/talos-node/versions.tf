terraform {
  required_version = ">= 1.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.84"
    }
    talos = {
      source  = "siderolabs/talos"
      version = ">= 0.9.0"
    }
  }
}
