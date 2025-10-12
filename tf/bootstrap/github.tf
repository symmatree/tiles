variable "github_token" {
  description = "GitHub token with appropriate permissions"
  type        = string
  sensitive   = true
}

variable "github_owner" {
  description = "GitHub owner (user or organization)"
  type        = string
}

provider "github" {
  token = var.github_token
  owner = var.github_owner
}

import {
  id = "tiles"
  to = github_repository.tiles
}

resource "github_repository" "tiles" {
  name          = "tiles"
  description   = "Infrastructure as Code for Tiles"
  visibility    = "public"
  has_issues    = true
  has_wiki      = false
  has_projects  = false
  has_downloads = false
}

locals {
  sa_mapping = {
    "tiles" = {
      sa_name   = google_service_account.tiles-tf.email
      attribute = "attribute.repository/${var.github_owner}/${github_repository.tiles.name}"
    }
  }
}

# module "gh_oidc" {
#   source      = "terraform-google-modules/github-actions-runners/google//modules/gh-oidc"
#   project_id  = var.gcp_project_id
#   pool_id     = "tiles-pool"
#   provider_id = "tiles-gh-provider"
#   sa_mapping = local.sa_mapping
# }


resource "google_service_account_iam_member" "self_impersonate" {
  service_account_id = google_service_account.tiles-tf.id
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.tiles-tf.email}"
}

resource "github_actions_secret" "gcp_tiles_tf_sa_email" {
  repository      = github_repository.tiles.name
  secret_name     = "GCP_TILES_TF_SA_EMAIL"
  plaintext_value = google_service_account.tiles-tf.email
}

resource "github_actions_secret" "gcp_tiles_tf_sa_key" {
  repository      = github_repository.tiles.name
  secret_name     = "GCP_TILES_TF_SA_KEY"
  plaintext_value = base64decode(google_service_account_key.tiles-tf.private_key)
}

resource "github_actions_secret" "project_id" {
  repository      = github_repository.tiles.name
  secret_name     = "PROJECT_ID"
  plaintext_value = var.gcp_project_id
}

resource "github_actions_secret" "proxmox_tiles_tf_token_id" {
  repository      = github_repository.tiles.name
  secret_name     = "PROXMOX_TILES_TF_TOKEN_ID"
  plaintext_value = proxmox_virtual_environment_user_token.user_token.id
}

resource "github_actions_secret" "proxmox_tiles_tf_token_value" {
  repository      = github_repository.tiles.name
  secret_name     = "PROXMOX_TILES_TF_TOKEN_VALUE"
  plaintext_value = proxmox_virtual_environment_user_token.user_token.value
}
