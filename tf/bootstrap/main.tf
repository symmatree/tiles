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
      version = ">= 5.0"
    }
  }
  backend "gcs" {
    bucket = "custodes-tf-state"
    prefix = "terraform/tiles/bootstrap"
  }
}
