terraform {
  required_version = ">= 1.0"
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = ">= 0.10.0"
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
