
provider "proxmox" {
  endpoint = data.onepassword_item.proxmox_root_user.url
  # Assume the root user is in the PAM realm.
  username = "${data.onepassword_item.proxmox_root_user.username}@pam"
  password = data.onepassword_item.proxmox_root_user.password
  insecure = true  # Invalid cert
}

resource "random_password" "proxmox_tiles_tf_password" {
  length           = 16
  special          = true
  override_special = "_%@"
}

resource "proxmox_virtual_environment_group" "admin_group" {
  comment  = "Managed by Terraform"
  group_id = "admin"
  acl {
    path      = "/"
    propagate = true
    role_id   = "Administrator"
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
