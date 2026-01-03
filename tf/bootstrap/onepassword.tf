
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

data "onepassword_item" "unifi_sa" {
  vault = data.onepassword_vault.tf_secrets.uuid
  title = "morpheus-terraform"
}

data "onepassword_item" "proxmox_root_user" {
  vault = data.onepassword_vault.tf_secrets.uuid
  title = "proxmox-root"
}

# Secrets we create

resource "onepassword_item" "proxmox_user_token" {
  vault    = data.onepassword_vault.tf_secrets.uuid
  title    = "proxmox_tiles_tf_token"
  category = "login"
  username = proxmox_virtual_environment_user_token.user_token.id
  password = proxmox_virtual_environment_user_token.user_token.value
  # Pass along url so the downstream doesn't need the root user secret.
  url = data.onepassword_item.proxmox_root_user.url
  section {
    label = "metadata"
    field {
      label = "source"
      value = "managed by terraform"
    }
    field {
      label = "root_module"
      value = basename(abspath(path.root))
    }
    field {
      label = "module"
      value = basename(abspath(path.module))
    }
  }
}
