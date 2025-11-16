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

variable "project_id" {
  type        = string
  description = "Google Cloud project ID"
}

data "onepassword_vault" "tf_secrets" {
  name = var.onepassword_vault_name
}

data "onepassword_item" "proxmox_user_token" {
  vault = data.onepassword_vault.tf_secrets.uuid
  title = "proxmox_tiles_tf_token"
}

provider "proxmox" {
  endpoint  = data.onepassword_item.proxmox_user_token.url
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

locals {
  test_vms = {
    "tiles-test-cp" : {
      type              = "control"
      proxmox_node_name = "nuc-g3p-2"
      vm_id             = 7411
      cores             = 1
      ram_mb            = 3000
      mac_address       = "bc:24:11:d0:74:11"
      ip_address        = "10.0.105.11"
    }
    "tiles-test-wk" : {
      type              = "worker"
      proxmox_node_name = "nuc-g3p-2"
      vm_id             = 7421
      cores             = 3
      ram_mb            = 11000
      mac_address       = "bc:24:11:d0:74:21"
      ip_address        = "10.0.105.21"
    }
  }

  prod_vms = {
    "tiles-cp-1" : {
      type              = "control"
      proxmox_node_name = "nuc-g2p-1"
      vm_id             = 7211
      cores             = 1
      ram_mb            = 3000
      mac_address       = "bc:24:11:d0:72:11"
      ip_address        = "10.0.101.11"
    }
    "tiles-cp-2" : {
      type              = "control"
      proxmox_node_name = "nuc-g2p-2"
      vm_id             = 7212
      cores             = 1
      ram_mb            = 3000
      mac_address       = "bc:24:11:d0:72:12"
      ip_address        = "10.0.101.12"
    }
    "tiles-cp-3" : {
      type              = "control"
      proxmox_node_name = "nuc-g3p-1"
      vm_id             = 7213
      cores             = 1
      ram_mb            = 3000
      mac_address       = "bc:24:11:d0:72:13"
      ip_address        = "10.0.101.13"
    }
    "tiles-wk-1" : {
      type              = "worker"
      proxmox_node_name = "nuc-g2p-1"
      vm_id             = 7221
      cores             = 3
      ram_mb            = 7000
      mac_address       = "bc:24:11:d0:72:21"
      ip_address        = "10.0.101.21"
    }
    "tiles-wk-2" : {
      type              = "worker"
      proxmox_node_name = "nuc-g2p-2"
      vm_id             = 7222
      cores             = 3
      ram_mb            = 7000
      mac_address       = "bc:24:11:d0:72:22"
      ip_address        = "10.0.101.22"
    }
    "tiles-wk-3" : {
      type              = "worker"
      proxmox_node_name = "nuc-g3p-1"
      vm_id             = 7223
      cores             = 3
      ram_mb            = 11000
      mac_address       = "bc:24:11:d0:72:23"
      ip_address        = "10.0.101.23"
    }
  }
}
