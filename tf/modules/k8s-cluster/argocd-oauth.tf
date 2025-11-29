# Google OAuth Client for ArgoCD Dex integration
#
# Note: The OAuth consent screen must be configured manually in the Google Cloud Console first:
# 1. Go to https://console.cloud.google.com/apis/credentials/consent
# 2. Configure the consent screen with:
#    - Application name
#    - User support email
#    - Authorized domains (e.g., symmatree.com)
#    - Scopes: openid, .../auth/userinfo.profile
#
# This Terraform file creates the OAuth Client ID using google_iam_oauth_client
# and stores credentials in 1Password.

variable "argocd_url" {
  description = "The full URL of the ArgoCD instance (e.g., https://argocd.tiles-test.symmatree.com)"
  type        = string
}

# Create OAuth client using google_iam_oauth_client resource
# Reference: https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/iam_oauth_client
# Note: The bootstrap grants roles/iam.oauthClientAdmin to the Terraform service account
resource "google_iam_oauth_client" "argocd" {
  project               = var.project_id
  location              = "global"
  oauth_client_id       = "${var.cluster_name}-argocd-oauth"
  display_name          = "${var.cluster_name}-argocd-oauth"
  client_type           = "CONFIDENTIAL_CLIENT"
  allowed_grant_types   = ["AUTHORIZATION_CODE_GRANT"]
  allowed_scopes        = ["openid", "email"]
  allowed_redirect_uris = ["${var.argocd_url}/api/dex/callback"]
}

# Create OAuth client credential to get the client secret
# Reference: https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/iam_oauth_client_credential
resource "google_iam_oauth_client_credential" "argocd" {
  project                    = var.project_id
  location                   = "global"
  oauthclient                = google_iam_oauth_client.argocd.name
  oauth_client_credential_id = "${var.cluster_name}-argocd-oauth-credential"
}

# Store credentials in 1Password
resource "onepassword_item" "argocd_google_oauth" {
  vault    = var.onepassword_vault
  title    = "argocd-google-oauth"
  category = "secure_note"

  section {
    label = "credentials"
    field {
      label = "OAUTH_CLIENT_ID"
      value = google_iam_oauth_client.argocd.client_id
      type  = "CONCEALED"
    }
    field {
      label = "OAUTH_CLIENT_SECRET"
      value = google_iam_oauth_client_credential.argocd.client_secret
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
    field {
      label = "cluster_name"
      value = var.cluster_name
    }
    field {
      label = "argocd_url"
      value = var.argocd_url
    }
  }
}
