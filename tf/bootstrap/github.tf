variable "github_owner" {
  description = "GitHub owner (user or organization)"
  type        = string
}

variable "github_token" {
  description = "GitHub token - used for provider authentication and stored in 1Password"
  type        = string
  sensitive   = true
}

provider "github" {
  token = var.github_token
  owner = var.github_owner
}

# Store the GitHub token used by terraform in 1Password with metadata
module "github_tf_bootstrap_token" {
  source = "../modules/github-app-token"

  vault_uuid        = data.onepassword_vault.tf_secrets.uuid
  token_name        = "github-tiles-tf-bootstrap"
  token_value       = var.github_token
  token_description = "GitHub PAT for Terraform provider in tf/bootstrap - manages GitHub repository configuration"

  expiration_days = 90

  token_permissions = {
    administration = "write"
    contents       = "write"
    metadata       = "read"
    secrets        = "write"
    workflows      = "write"
  }

  token_repositories = [github_repository.tiles.name]
}

# Create token for Grafana GitHub data source
module "grafana_github_token" {
  source = "../modules/github-app-token"

  vault_uuid        = data.onepassword_vault.tf_secrets.uuid
  token_name        = "grafana-github-token"
  token_value       = var.github_token # Using same token for now, can be separate later
  token_description = "GitHub PAT for Grafana GitHub data source - read-only access to repository data"

  expiration_days = 90

  token_permissions = {
    contents      = "read"
    metadata      = "read"
    pull_requests = "read"
    issues        = "read"
  }

  token_repositories = [github_repository.tiles.name]
}


resource "github_repository" "tiles" {
  name                   = "tiles"
  description            = "Infrastructure as Code for Tiles"
  visibility             = "public"
  has_issues             = true
  has_wiki               = false
  has_projects           = false
  allow_merge_commit     = false
  allow_auto_merge       = true
  allow_rebase_merge     = false
  allow_squash_merge     = true
  delete_branch_on_merge = true
  vulnerability_alerts   = true
  allow_update_branch    = true
  security_and_analysis {
    secret_scanning {
      status = "enabled"
    }
    secret_scanning_push_protection {
      status = "enabled"
    }
  }
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
        context        = "nodes-plan-apply"
        integration_id = 15368
      }
      required_check {
        context        = "pre-commit"
        integration_id = 15368
      }
    }
  }
}

resource "github_repository_ruleset" "tiles-tags" {
  name        = "tiles-tags"
  repository  = github_repository.tiles.name
  target      = "tag"
  enforcement = "active"

  bypass_actors {
    actor_id    = 5
    actor_type  = "RepositoryRole"
    bypass_mode = "always"
  }

  conditions {
    ref_name {
      include = ["refs/tags/test", "refs/tags/prod"]
      exclude = []
    }
  }

  rules {
    deletion = true
    update   = true
  }
}

module "secret_onepassword_sa_token" {
  source          = "../modules/github-secret"
  repository      = github_repository.tiles.name
  secret_name     = "ONEPASSWORD_SA_TOKEN"
  plaintext_value = var.onepassword_sa_token
}

resource "github_repository" "polisher" {
  name                   = "polisher"
  description            = "Infrastructure as Code for Polisher"
  visibility             = "public"
  has_issues             = true
  has_wiki               = false
  has_projects           = false
  allow_merge_commit     = false
  allow_auto_merge       = true
  allow_rebase_merge     = false
  allow_squash_merge     = true
  delete_branch_on_merge = true
  vulnerability_alerts   = true
  allow_update_branch    = true
  security_and_analysis {
    secret_scanning {
      status = "enabled"
    }
    secret_scanning_push_protection {
      status = "enabled"
    }
  }
}

resource "github_repository_ruleset" "polisher-main" {
  enforcement = "active"
  name        = "polisher-main"
  repository  = github_repository.polisher.name
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
        context        = "nodes-plan-apply"
        integration_id = 15368
      }
      required_check {
        context        = "pre-commit"
        integration_id = 15368
      }
    }
  }
}

resource "github_repository_ruleset" "polisher-tags" {
  name        = "polisher-tags"
  repository  = github_repository.polisher.name
  target      = "tag"
  enforcement = "active"

  bypass_actors {
    actor_id    = 5
    actor_type  = "RepositoryRole"
    bypass_mode = "always"
  }

  conditions {
    ref_name {
      include = ["refs/tags/test", "refs/tags/prod"]
      exclude = []
    }
  }

  rules {
    deletion = true
    update   = true
  }
}

module "secret_onepassword_sa_token_polisher" {
  source      = "../modules/github-secret"
  repository  = github_repository.polisher.name
  secret_name = "ONEPASSWORD_SA_TOKEN"
  # We share the 1password vault and service account
  plaintext_value = var.onepassword_sa_token
}
