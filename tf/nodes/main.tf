
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

provider "proxmox" {
  alias     = "proxmox_root"
  endpoint  = data.onepassword_item.proxmox_user_token.url
  username  = "root@pam"
  password  = var.proxmox_root_password
  insecure  = true
}

provider "unifi" {
  # Authentication via UNIFI_USERNAME and UNIFI_PASSWORD environment variables
  api_url        = var.unifi_controller_url
  allow_insecure = true
}

data "onepassword_item" "cloudflare_api_token" {
  vault = data.onepassword_vault.tf_secrets.uuid
  title = "cloudflare-api-token"
}

provider "cloudflare" {
  api_token = data.onepassword_item.cloudflare_api_token.password
}

provider "synology" {
  # Authentication via SYNOLOGY_USER and SYNOLOGY_PASSWORD environment variables
  # Host can be set via SYNOLOGY_HOST environment variable or here
  host = var.synology_host
}

data "proxmox_virtual_environment_nodes" "nodes" {}
