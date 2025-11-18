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
    github = {
      source  = "integrations/github"
      version = "< 6.8.4"
    }
    unifi = {
      source  = "ubiquiti-community/unifi"
      version = ">= 0.41.3"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = ">= 2.1.2"
    }
  }
  backend "gcs" {
    bucket = "custodes-tf-state"
    prefix = "terraform/tiles/bootstrap"
  }
}

variable "unifi_controller_url" {
  description = "Unifi Controller URL"
  type        = string
  default     = "https://morpheus.local.symmatree.com:443"
}

provider "unifi" {
  username       = data.onepassword_item.unifi_sa.username
  password       = data.onepassword_item.unifi_sa.password
  api_url        = var.unifi_controller_url
  allow_insecure = true
}
