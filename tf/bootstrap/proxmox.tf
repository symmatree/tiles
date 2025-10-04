
variable "proxmox_endpoint" {
  description = "Proxmox VE API endpoint"
  type        = string
}

variable "proxmox_username" {
  description = "Proxmox VE username"
  type        = string
}

variable "proxmox_password" {
  description = "Proxmox VE password"
  type        = string
  sensitive   = true
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  username = var.proxmox_username
  password = var.proxmox_password
  insecure = true
}

resource "random_password" "proxmox_tiles_tf_password" {
  length           = 16
  special          = true
  override_special = "_%@"
}

output "proxmox_tiles_tf_password" {
  description = "The password for the Proxmox VE tiles-tf user. Store this securely!"
  value       = random_password.proxmox_tiles_tf_password.result
  sensitive   = true
}

resource "proxmox_virtual_environment_group" "admin_group" {
  comment  = "Managed by Terraform"
  group_id = "admin"
  acl {
    path    = "/"
    role_id = "Administrator"
  }
}

resource "proxmox_virtual_environment_user" "tiles_tf" {
  comment         = "Managed by Terraform"
  email           = "tiles-tf@pve"
  enabled         = true
  expiration_date = "2034-01-01T22:00:00Z"
  user_id         = "tiles-tf@pve"
  groups          = [proxmox_virtual_environment_group.admin_group.group_id]
  password        = random_password.proxmox_tiles_tf_password.result
}

resource "proxmox_virtual_environment_user_token" "user_token" {
  comment               = "Managed by Terraform"
  expiration_date       = "2033-01-01T22:00:00Z"
  token_name            = "tiles_tf_token"
  user_id               = proxmox_virtual_environment_user.tiles_tf.user_id
  privileges_separation = false
}

output "proxmox_tiles_tf_user_id" {
  description = "The Proxmox VE user ID for the tiles-tf user."
  value       = proxmox_virtual_environment_user.tiles_tf.user_id
}
output "proxmox_tiles_tf_token_id" {
  description = "The Proxmox VE token ID for the tiles-tf user."
  value       = proxmox_virtual_environment_user_token.user_token.id
}
output "proxmox_tiles_tf_token_value" {
  description = "The Proxmox VE token value for the tiles-tf user. Store this securely!"
  value       = proxmox_virtual_environment_user_token.user_token.value
  sensitive   = true
}
