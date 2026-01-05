terraform {
  required_version = ">= 1.0"
  required_providers {
    unifi = {
      source  = "ubiquiti-community/unifi"
      version = ">= 0.41.3"
    }
    talos = {
      source  = "siderolabs/talos"
      version = ">= 0.9.0"
    }
  }
}
