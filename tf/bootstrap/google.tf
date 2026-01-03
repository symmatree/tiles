variable "seed_project_id" {
  description = "The GCP project ID to deploy resources into."
  type        = string
}

variable "gcp_region" {
  description = "The GCP region to deploy resources into."
  type        = string
}

provider "google" {
  project               = var.seed_project_id
  billing_project       = var.seed_project_id
  user_project_override = true
  # region = var.gcp_region
}

variable "gcp_owner_email" {
  description = "Email of the GCP project owner for IAM assignment"
  type        = string
}

resource "google_project_iam_member" "self-iam-admin" {
  project = var.seed_project_id
  role    = "roles/owner"
  member  = "user:${var.gcp_owner_email}"
}

# Enable required APIs
resource "google_project_service" "kms_api" {
  project = var.seed_project_id
  service = "cloudkms.googleapis.com"

  disable_on_destroy = false
}

resource "google_project_service" "seed_billing_budgets_api" {
  project = var.seed_project_id
  service = "billingbudgets.googleapis.com"

  disable_on_destroy = false
  depends_on         = [google_project_service.seed_service_usage_api]
}

resource "google_project_service" "seed_essential_contacts_api" {
  project = var.seed_project_id
  service = "essentialcontacts.googleapis.com"

  disable_on_destroy = false
  depends_on         = [google_project_service.seed_service_usage_api]
}

resource "google_project_service" "seed_service_usage_api" {
  project = var.seed_project_id
  service = "serviceusage.googleapis.com"

  disable_on_destroy = false
}

module "gcp_state_bucket" {
  source  = "terraform-google-modules/cloud-storage/google//modules/simple_bucket"
  version = ">= 12.0"

  name                     = "custodes-tf-state"
  project_id               = var.seed_project_id
  location                 = var.gcp_region
  public_access_prevention = "enforced"
  iam_members = [
    {
      role   = "roles/storage.objectUser"
      member = "serviceAccount:${google_service_account.tiles_terraform_oidc.email}"
    },
    {
      role   = "roles/storage.admin"
      member = "user:${var.gcp_owner_email}"
    },
  ]
  depends_on = [google_service_account.tiles_terraform_oidc]
}
