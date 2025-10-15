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
  backend "gcs" {
    bucket = "custodes-tf-state"
    prefix = "terraform/tiles/nodes"
  }
}

data "terraform_remote_state" "bootstrap" {
  backend = "gcs"
  config = {
    bucket = "custodes-tf-state"
    prefix = "terraform/tiles/bootstrap"
  }
}

locals {
  proxmox_tiles_tf_user_id     = data.terraform_remote_state.bootstrap.outputs.proxmox_tiles_tf_user_id
  proxmox_tiles_tf_token_id    = data.terraform_remote_state.bootstrap.outputs.proxmox_tiles_tf_token_id
  proxmox_tiles_tf_token_value = data.terraform_remote_state.bootstrap.outputs.proxmox_tiles_tf_token_value
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  # api_token = "${local.proxmox_tiles_tf_user_id}!provider=${local.proxmox_tiles_tf_token_value}"
  api_token = local.proxmox_tiles_tf_token_value
  insecure  = true
}

provider "unifi" {
  username       = "terraform"
  password       = var.unifi_password
  api_url        = var.unifi_controller_url
  allow_insecure = true
}

data "proxmox_virtual_environment_nodes" "nodes" {}
