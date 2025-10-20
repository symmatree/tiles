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
  }
  backend "gcs" {
    bucket = "custodes-tf-state"
    prefix = "terraform/tiles/nodes"
  }
}

variable "onepassword_sa_token" {
  description = "1Password service account token"
  type        = string
}

provider "onepassword" {
  # url = "https://my.1password.com"
  service_account_token = var.onepassword_sa_token
}

variable "onepassword_vault_name" {
  type        = string
  description = "The name of the 1Password vault to use for storing secrets."
}

data "onepassword_vault" "tf_secrets" {
  name = var.onepassword_vault_name
}

data "onepassword_item" "proxmox_user_token" {
  vault = data.onepassword_vault.tf_secrets.uuid
  title = "proxmox_tiles_tf_token"
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = data.onepassword_item.proxmox_user_token.password
  insecure  = true
}

data "onepassword_item" "unifi_sa" {
  vault = data.onepassword_vault.tf_secrets.uuid
  title = "morpheus-terraform"
}

provider "unifi" {
  username       = data.onepassword_item.unifi_sa.username
  password       = data.onepassword_item.unifi_sa.password
  api_url        = var.unifi_controller_url
  allow_insecure = true
}

data "proxmox_virtual_environment_nodes" "nodes" {}
