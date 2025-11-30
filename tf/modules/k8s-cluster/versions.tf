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
  }
}
