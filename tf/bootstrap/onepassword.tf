
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

# VPN Config created manually in Unifi UI.
data "onepassword_item" "github-vpn-config" {
  vault = data.onepassword_vault.tf_secrets.uuid
  title = "github-vpn-config"
}

data "onepassword_item" "github_token" {
  vault = data.onepassword_vault.tf_secrets.uuid
  title = "github-tiles-tf-bootstrap"
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

resource "onepassword_item" "gcp_tiles_tf_sa" {
  vault    = data.onepassword_vault.tf_secrets.uuid
  title    = "gcp_tiles_tf_sa"
  category = "login"
  username = google_service_account.tiles-tf.email
  password = base64decode(google_service_account_key.tiles-tf.private_key)
  section {
    label = "metadata"
    field {
      label = "managed_by"
      value = "terraform"
    }
    field {
      label = "workspace"
      value = terraform.workspace
    }
  }
}

resource "onepassword_item" "proxmox_user_token" {
  vault    = data.onepassword_vault.tf_secrets.uuid
  title    = "proxmox_tiles_tf_token"
  category = "login"
  username = proxmox_virtual_environment_user_token.user_token.id
  password = proxmox_virtual_environment_user_token.user_token.value
  section {
    label = "metadata"
    field {
      label = "managed_by"
      value = "terraform"
    }
    field {
      label = "workspace"
      value = terraform.workspace
    }
  }
}
