
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
