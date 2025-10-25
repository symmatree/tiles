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

resource "github_repository_ruleset" "tiles-main" {
  enforcement = "active"
  name        = "tiles-main"
  repository  = github_repository.tiles.name
  target      = "branch"
  bypass_actors {
    actor_id    = 5
    actor_type  = "RepositoryRole"
    bypass_mode = "pull_request"
  }
  conditions {
    ref_name {
      exclude = []
      include = ["~DEFAULT_BRANCH"]
    }
  }
  rules {
    creation                = true
    deletion                = true
    non_fast_forward        = true
    required_linear_history = true
    pull_request {
      required_approving_review_count = 0
    }
    required_status_checks {
      required_check {
        context        = "plan-apply"
        integration_id = 15368
      }
      required_check {
        context        = "pre-commit"
        integration_id = 15368
      }
    }
  }
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

module "secret_tf_sa_email" {
  source          = "../modules/github-secret"
  repository      = github_repository.tiles.name
  secret_name     = "GCP_TILES_TF_SA_EMAIL"
  plaintext_value = google_service_account.tiles-tf.email
}

module "secret_tf_sa_key" {
  source          = "../modules/github-secret"
  repository      = github_repository.tiles.name
  secret_name     = "GCP_TILES_TF_SA_KEY"
  plaintext_value = base64decode(google_service_account_key.tiles-tf.private_key)
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

module "secret_vpn_config" {
  source          = "../modules/github-secret"
  repository      = github_repository.tiles.name
  secret_name     = "TILES_VPN_CONFIG"
  plaintext_value = local.vpn_config.value
}

module "secret_onepassword_sa_token" {
  source          = "../modules/github-secret"
  repository      = github_repository.tiles.name
  secret_name     = "ONEPASSWORD_SA_TOKEN"
  plaintext_value = var.onepassword_sa_token
}
