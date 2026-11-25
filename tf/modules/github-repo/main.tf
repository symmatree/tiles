terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

variable "name" {
  description = "Repository name, unqualified by owner"
  type        = string
}

variable "description" {
  description = "Repository description shown on GitHub"
  type        = string
}

variable "required_checks" {
  description = <<-EOT
    Status check contexts that must pass before the default branch accepts a
    merge. Only checks that run on every pull request belong here: a
    path-filtered workflow leaves the context pending forever on a PR that does
    not touch its paths. Empty for a repository with no CI yet.
  EOT
  type        = list(string)
  default     = []
}

variable "deploy_tags" {
  description = "Protect the `test` and `prod` deploy tags from deletion"
  type        = bool
  default     = false
}

# The GitHub Actions app. Pinning each required check to it means a same-named
# check reported by some other app cannot satisfy the rule.
locals {
  github_actions_app_id = 15368
}

resource "github_repository" "this" {
  name        = var.name
  description = var.description
  visibility  = "public"

  has_issues   = true
  has_wiki     = false
  has_projects = false

  # Merge commits only. The branch's commits land on main unchanged, so git
  # sees a merged branch as merged; rebase and squash both write new commits.
  # The merge commit takes the PR's title and description.
  allow_merge_commit   = true
  allow_squash_merge   = false
  allow_rebase_merge   = false
  merge_commit_title   = "PR_TITLE"
  merge_commit_message = "PR_BODY"
  allow_auto_merge     = true
  allow_update_branch  = true

  delete_branch_on_merge = true
  vulnerability_alerts   = true

  security_and_analysis {
    secret_scanning {
      status = "enabled"
    }
    secret_scanning_push_protection {
      status = "enabled"
    }
  }
}

resource "github_repository_ruleset" "main" {
  name        = "${var.name}-main"
  repository  = github_repository.this.name
  target      = "branch"
  enforcement = "active"

  bypass_actors {
    actor_id    = 5 # RepositoryRole: admin
    actor_type  = "RepositoryRole"
    bypass_mode = "pull_request"
  }

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    creation         = true
    deletion         = true
    non_fast_forward = true

    pull_request {
      # Solo repositories: the gate is CI, not a second pair of eyes.
      required_approving_review_count = 0
      allowed_merge_methods           = ["merge"]
    }

    dynamic "required_status_checks" {
      for_each = length(var.required_checks) > 0 ? [1] : []
      content {
        dynamic "required_check" {
          for_each = var.required_checks
          content {
            context        = required_check.value
            integration_id = local.github_actions_app_id
          }
        }
      }
    }
  }
}

resource "github_repository_ruleset" "tags" {
  count = var.deploy_tags ? 1 : 0

  name        = "${var.name}-tags"
  repository  = github_repository.this.name
  target      = "tag"
  enforcement = "active"

  bypass_actors {
    actor_id    = 5 # RepositoryRole: admin
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
  }
}

output "name" {
  description = "Repository name, for wiring up secrets and other per-repo resources"
  value       = github_repository.this.name
}
