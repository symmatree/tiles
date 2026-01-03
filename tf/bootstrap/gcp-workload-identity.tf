# GitHub OIDC Workload Identity Setup
# Reference: https://registry.terraform.io/modules/terraform-google-modules/github-actions-runners/google/latest/submodules/gh-oidc

variable "github_repository" {
  description = "GitHub repository in the format 'owner/repo'"
  type        = string
}

# Set up GitHub OIDC workload identity pool
module "gh_oidc" {
  source  = "terraform-google-modules/github-actions-runners/google//modules/gh-oidc"
  version = ">= 4.1"

  project_id  = module.tiles_id_project.project_id
  pool_id     = "github-pool"
  provider_id = "github-provider"

  # I think this is what prevents other people from using valid github creds
  # (but nothing to do with us) from using them against this pool and provider.
  attribute_condition = "assertion.repository_owner=='${var.github_owner}'"

  sa_mapping = {
    "tiles-terraform-sa" = {
      sa_name   = "projects/${module.tiles_id_project.project_id}/serviceAccounts/${google_service_account.tiles_terraform_oidc.email}"
      attribute = "attribute.repository/${var.github_repository}"
    }
  }
}

# Create service account for Terraform operations via OIDC
resource "google_service_account" "tiles_terraform_oidc" {
  project      = module.tiles_id_project.project_id
  account_id   = "tiles-terraform-oidc"
  display_name = "Tiles Terraform OIDC Service Account"
  description  = "Service account for GitHub Actions to run Terraform via OIDC"
}

# Define project permissions for the OIDC service account
# Shared roles for tiles-main and tiles-test-main to ensure they stay in sync
locals {
  tiles_main_roles = [
    "roles/editor",
    "roles/storage.admin",
    "roles/dns.admin",
    "roles/resourcemanager.projectIamAdmin",
    "roles/iam.securityAdmin"
  ]

  project_permissions = {
    "tiles-id" = {
      project_id = module.tiles_id_project.project_id
      roles      = ["roles/viewer"]
    }
    "tiles-kms" = {
      project_id = module.tiles_kms_project.project_id
      roles      = ["roles/cloudkms.admin"]
    }
    "tiles-main" = {
      project_id = module.tiles_main_project.project_id
      roles      = local.tiles_main_roles
    }
    "tiles-test-main" = {
      project_id = module.tiles_test_main_project.project_id
      roles      = local.tiles_main_roles
    }
    "seed" = {
      project_id = var.seed_project_id
      roles = [
        "roles/editor",
        "roles/storage.admin",
        "roles/dns.admin",
        "roles/resourcemanager.projectIamAdmin",
        "roles/iam.securityAdmin"
      ]
    }
  }

  # Flatten project_permissions into a map keyed by "project-role" for for_each
  iam_members = merge([
    for project_key, project_config in local.project_permissions : {
      for role in project_config.roles : "${project_key}-${role}" => {
        project_id  = project_config.project_id
        role        = role
        project_key = project_key
      }
    }
  ]...)
}

# Grant permissions to the OIDC service account on all projects
resource "google_project_iam_member" "tiles_terraform_oidc" {
  for_each = local.iam_members

  project = each.value.project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.tiles_terraform_oidc.email}"
}

# Store workload identity credentials in 1Password
resource "onepassword_item" "gh_oidc_provider" {
  vault    = data.onepassword_vault.tf_secrets.uuid
  title    = "gh_oidc_workload_identity"
  category = "login"

  username = google_service_account.tiles_terraform_oidc.email

  section {
    label = "fields"

    field {
      label = "workload_identity_provider"
      type  = "STRING"
      value = module.gh_oidc.provider_name
    }

    field {
      label = "service_account_email"
      type  = "STRING"
      value = google_service_account.tiles_terraform_oidc.email
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

# Outputs
output "workload_identity_provider" {
  description = "The workload identity provider name for GitHub Actions"
  value       = module.gh_oidc.provider_name
}

output "tiles_terraform_oidc_sa_email" {
  description = "The email of the Tiles Terraform OIDC service account"
  value       = google_service_account.tiles_terraform_oidc.email
}
