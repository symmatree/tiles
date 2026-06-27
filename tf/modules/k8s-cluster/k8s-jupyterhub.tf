# Component: JupyterHub
# Documentation: charts/jupyterhub/README.md
# Application: charts/jupyterhub/application.yaml
# Generates hub secrets (cookie_secret, CryptKeeper.keys) and stores them in
# 1Password. The chart reads them at runtime via hub.existingSecret so the
# chart-managed Secret's auto-generated values are never used for these two.
# proxy.secretToken (auth_token) is left to chart auto-generation; it is
# stable across upgrades via lookup() and cannot be overridden via existingSecret.

resource "random_password" "jupyterhub_cookie_secret" {
  length  = 64
  special = false
}

resource "random_password" "jupyterhub_crypt_key" {
  length  = 64
  special = false
}

resource "onepassword_item" "jupyterhub_hub_credentials" {
  vault    = var.onepassword_vault
  title    = "${var.cluster_name}-jupyterhub-hub-credentials"
  category = "secure_note"

  section {
    label = "credentials"
    field {
      label = "hub.config.JupyterHub.cookie_secret"
      value = random_password.jupyterhub_cookie_secret.result
      type  = "CONCEALED"
    }
    field {
      label = "hub.config.CryptKeeper.keys"
      value = random_password.jupyterhub_crypt_key.result
      type  = "CONCEALED"
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
