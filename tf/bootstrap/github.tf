variable "github_owner" {
  description = "GitHub owner (user or organization)"
  type        = string
}

variable "github_token" {
  description = "GitHub token"
  type        = string
  sensitive   = true
}

provider "github" {
  # Staged through TF_VAR_github_token; see README.md.
  token = var.github_token
  owner = var.github_owner
}

# Repository policy -- merge mode, ruleset shape, security settings -- lives in
# modules/github-repo and is the same everywhere. Only what genuinely differs
# per repository is spelled out here.
locals {
  repos = {
    tiles = {
      description     = "Infrastructure as Code for Tiles"
      required_checks = ["pre-commit", "nodes-plan-apply"]
      deploy_tags     = true
    }
    polisher = {
      description     = "Infrastructure as Code for Polisher"
      required_checks = ["pre-commit", "nodes-plan-apply"]
      deploy_tags     = true
    }
    coordinator = {
      description = "on-vehicle companion device for Ardupilot / Ardurover providing OAK-D VIO, time sync, usb-gadget network bridging"
      # containers-ok and firmware-ok are the gate jobs of build-containers and
      # build-firmware: they always run and report the result of the matrix
      # behind them, which a path-filtered build job cannot do. `tests` runs the
      # workstation suite. See the repository's docs/ci.md.
      required_checks = ["pre-commit", "containers-ok", "firmware-ok", "tests"]
      deploy_tags     = false
    }
    dotfiles-symm = {
      description     = "Dotfiles and environment setup"
      required_checks = ["pre-commit"]
      deploy_tags     = false
    }
    fables = {
      description     = "Public technical notes: GNSS, mapping, robotics, hardware"
      required_checks = ["pre-commit"]
      deploy_tags     = false
    }
  }
}

module "repo" {
  source   = "../modules/github-repo"
  for_each = local.repos

  name            = each.key
  description     = each.value.description
  required_checks = each.value.required_checks
  deploy_tags     = each.value.deploy_tags
}

# Only the repositories whose CI reads the shared tiles-secrets vault. The
# 1Password service account is shared, so both get the same token.
module "secret_onepassword_sa_token" {
  source   = "../modules/github-secret"
  for_each = toset(["tiles", "polisher"])

  repository      = module.repo[each.key].name
  secret_name     = "ONEPASSWORD_SA_TOKEN"
  plaintext_value = var.onepassword_sa_token
}
