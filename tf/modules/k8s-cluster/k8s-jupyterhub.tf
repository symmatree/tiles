# Component: JupyterHub
# Documentation: charts/jupyterhub/README.md
# Application: charts/jupyterhub/application.yaml
# Generates hub secrets (cookie_secret, CryptKeeper.keys) and stores them in
# 1Password. The chart reads them at runtime via hub.existingSecret so the
# chart-managed Secret's auto-generated values are never used for these two.
# proxy.secretToken (auth_token) is left to chart auto-generation; it is
# stable across upgrades via lookup() and cannot be overridden via existingSecret.

# cookie_secret: JupyterHub parses this as hex and decodes to 32 bytes → must
# be 64 lowercase hex characters. random_id.hex gives exactly that.
resource "random_id" "jupyterhub_cookie_secret" {
  byte_length = 32
}

# CryptKeeper.keys: Fernet key format — 32 random bytes, URL-safe base64 with
# padding. random_id.b64_url is 43 chars (no padding); 32 bytes needs one '='.
resource "random_id" "jupyterhub_crypt_key" {
  byte_length = 32
}

resource "onepassword_item" "jupyterhub_hub_credentials" {
  vault    = var.onepassword_vault
  title    = "${var.cluster_name}-jupyterhub-hub-credentials"
  category = "secure_note"

  section {
    label = "credentials"
    field {
      label = "hub.config.JupyterHub.cookie_secret"
      value = random_id.jupyterhub_cookie_secret.hex
      type  = "CONCEALED"
    }
    field {
      label = "hub.config.CryptKeeper.keys"
      value = "${random_id.jupyterhub_crypt_key.b64_url}="
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
