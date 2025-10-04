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
  name        = "tiles"
  description = "Infrastructure as Code for Tiles"
  visibility  = "public"
  has_issues = true
  has_wiki = false
  has_projects = false
  has_downloads = false
  
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
