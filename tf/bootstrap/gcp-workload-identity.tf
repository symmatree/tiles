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

  # Map GitHub OIDC claims to attributes (required for attribute conditions)
  # Override default to include repository mapping for sa_mapping conditions
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.actor"      = "assertion.actor"
    "attribute.aud"        = "assertion.aud"
  }

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

# Grant necessary permissions to the service account on tiles-id project
resource "google_project_iam_member" "tiles_terraform_oidc_id_viewer" {
  project = module.tiles_id_project.project_id
  role    = "roles/viewer"
  member  = "serviceAccount:${google_service_account.tiles_terraform_oidc.email}"
}

# Grant necessary permissions to the service account on tiles-kms project
resource "google_project_iam_member" "tiles_terraform_oidc_kms_admin" {
  project = module.tiles_kms_project.project_id
  role    = "roles/cloudkms.admin"
  member  = "serviceAccount:${google_service_account.tiles_terraform_oidc.email}"
}

# Grant necessary permissions to the service account on tiles-main project
resource "google_project_iam_member" "tiles_terraform_oidc_main_editor" {
  project = module.tiles_main_project.project_id
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.tiles_terraform_oidc.email}"
}

resource "google_project_iam_member" "tiles_terraform_oidc_main_storage_admin" {
  project = module.tiles_main_project.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.tiles_terraform_oidc.email}"
}

resource "google_project_iam_member" "tiles_terraform_oidc_main_dns_admin" {
  project = module.tiles_main_project.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.tiles_terraform_oidc.email}"
}

# Grant necessary permissions to the service account on tiles-test-main project
resource "google_project_iam_member" "tiles_terraform_oidc_test_main_editor" {
  project = module.tiles_test_main_project.project_id
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.tiles_terraform_oidc.email}"
}

resource "google_project_iam_member" "tiles_terraform_oidc_test_main_storage_admin" {
  project = module.tiles_test_main_project.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.tiles_terraform_oidc.email}"
}

resource "google_project_iam_member" "tiles_terraform_oidc_test_main_dns_admin" {
  project = module.tiles_test_main_project.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.tiles_terraform_oidc.email}"
}

# Also grant permissions on the existing seed project for backwards compatibility
resource "google_project_iam_member" "tiles_terraform_oidc_seed_editor" {
  project = var.seed_project_id
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.tiles_terraform_oidc.email}"
}

resource "google_project_iam_member" "tiles_terraform_oidc_seed_storage_admin" {
  project = var.seed_project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.tiles_terraform_oidc.email}"
}

resource "google_project_iam_member" "tiles_terraform_oidc_seed_dns_admin" {
  project = var.seed_project_id
  role    = "roles/dns.admin"
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
