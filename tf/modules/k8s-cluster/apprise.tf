# Component: Apprise
# Documentation: tanka/environments/apprise/README.md
# Application: tanka/environments/apprise/application.yaml
# This module creates 1Password secrets for Apprise configuration and admin credentials.

resource "random_password" "apprise_env" {
  length  = 24
  special = true
}

resource "onepassword_item" "apprise_env" {
  vault    = data.onepassword_vault.tf_secrets.uuid
  title    = "${var.cluster_name}-apprise-env"
  category = "secure_note"
  section {
    label = "config"
    field {
      label = "SECRET_KEY"
      value = random_password.apprise_env.result
    }
  }

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

resource "random_password" "apprise_admin" {
  length  = 24
  special = true
}

resource "htpasswd_password" "apprise_admin" {
  password = random_password.apprise_admin.result
}

resource "onepassword_item" "apprise_admin" {
  vault    = data.onepassword_vault.tf_secrets.uuid
  title    = "${var.cluster_name}-apprise-admin"
  category = "login"
  username = "apprise"
  password = random_password.apprise_admin.result
  url      = "https://apprise.${var.cluster_name}.symmatree.com"
  section {
    label = "credentials"
    field {
      label = ".htpasswd"
      value = <<-EOT
        ${var.cluster_name}:${htpasswd_password.apprise_admin.bcrypt}
        EOT
    }
  }

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
