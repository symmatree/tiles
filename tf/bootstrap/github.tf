variable "github_owner" {
  description = "GitHub owner (user or organization)"
  type        = string
}

provider "github" {
  token = data.onepassword_item.github_token.password
  owner = var.github_owner
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

locals {
  # This is a messy blind fetch so we check some things below
  vpn_config = data.onepassword_item.github-vpn-config.section[0].field[0]
}

# Validation to ensure VPN config is not empty
check "vpn_config_not_empty" {
  assert {
    condition     = startswith(local.vpn_config.value, "[Interface]") && local.vpn_config.label == "wireguard-config"
    error_message = "tiles_vpn_config must not be empty. Check your OnePassword item 'github-vpn-config'."
  }
}

resource "github_actions_secret" "tiles_vpn_config" {
  repository      = github_repository.tiles.name
  secret_name     = "TILES_VPN_CONFIG"
  plaintext_value = local.vpn_config.value
}

resource "github_actions_secret" "unifi_username" {
  repository      = github_repository.tiles.name
  secret_name     = "UNIFI_USERNAME"
  plaintext_value = data.onepassword_item.unifi_sa.username
}

resource "github_actions_secret" "unifi_password" {
  repository      = github_repository.tiles.name
  secret_name     = "UNIFI_PASSWORD"
  plaintext_value = data.onepassword_item.unifi_sa.password
}
