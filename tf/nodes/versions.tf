terraform {
  required_version = ">= 1.8"
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      # host_managed on LXC network_interface (Proxmox Alloy CTs) requires >= 0.104.
      version = ">= 0.104"
    }
    google = {
      source  = "hashicorp/google"
      version = ">= 7.0"
    }
    unifi = {
      source  = "ubiquiti-community/unifi"
      version = "0.46.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = ">= 0.9.0"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = ">= 2.1.2"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.11.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.7.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 4.0"
    }
    htpasswd = {
      source  = "loafoe/htpasswd"
      version = ">= 1.0.0"
    }
    synology = {
      source = "synology-community/synology"
      # Pinned to the version locked when synology-alloy landed (#264). Loosen after upstream
      # stream/JSON fix (go-synology / provider) or deliberate verification on newer DSM.
      version = "= 0.6.7"
    }
  }
  backend "gcs" {
    bucket = "custodes-tf-state"
    prefix = "terraform/tiles/nodes"
  }
}
