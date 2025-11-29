variable "gcp_project_id" {
  description = "The GCP project ID to deploy resources into."
  type        = string
}

variable "gcp_region" {
  description = "The GCP region to deploy resources into."
  type        = string
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

variable "gcp_owner_email" {
  description = "Email of the GCP project owner for IAM assignment"
  type        = string
}

resource "google_project_iam_member" "self-iam-admin" {
  project = var.gcp_project_id
  role    = "roles/owner"
  member  = "user:${var.gcp_owner_email}"
}

resource "google_service_account" "tiles-tf" {
  account_id   = "tiles-tf-sa"
  display_name = "Tiles TF Service Account"
}

resource "google_service_account_key" "tiles-tf" {
  service_account_id = google_service_account.tiles-tf.name
  public_key_type    = "TYPE_X509_PEM_FILE"
  private_key_type   = "TYPE_GOOGLE_CREDENTIALS_FILE"
}

resource "google_service_account_iam_member" "self_impersonate" {
  service_account_id = google_service_account.tiles-tf.id
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.tiles-tf.email}"
}

resource "google_project_iam_member" "tiles_tf_editor" {
  project = var.gcp_project_id
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.tiles-tf.email}"
}

resource "google_project_iam_member" "tiles_tf_storage_admin" {
  project = var.gcp_project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.tiles-tf.email}"
}

resource "google_project_iam_member" "tiles_tf_dns_admin" {
  project = var.gcp_project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.tiles-tf.email}"
}

resource "google_project_iam_member" "tiles_tf_project_iam_admin" {
  project = var.gcp_project_id
  role    = "roles/resourcemanager.projectIamAdmin"
  member  = "serviceAccount:${google_service_account.tiles-tf.email}"
}

resource "google_project_iam_member" "tiles_tf_iam_security_admin" {
  project = var.gcp_project_id
  role    = "roles/iam.securityAdmin"
  member  = "serviceAccount:${google_service_account.tiles-tf.email}"
}

resource "google_project_iam_member" "tiles_tf_oauth_client_admin" {
  project = var.gcp_project_id
  role    = "roles/iam.oauthClientAdmin"
  member  = "serviceAccount:${google_service_account.tiles-tf.email}"
}

output "gcp_tiles_tf_sa_email" {
  description = "The email of the Tiles TF service account."
  value       = google_service_account.tiles-tf.email
}

module "gcp_state_bucket" {
  source  = "terraform-google-modules/cloud-storage/google//modules/simple_bucket"
  version = ">= 12.0"

  name                     = "custodes-tf-state"
  project_id               = var.gcp_project_id
  location                 = var.gcp_region
  public_access_prevention = "enforced"
  iam_members = [
    {
      role   = "roles/storage.objectUser"
      member = "serviceAccount:${google_service_account.tiles-tf.email}"
    },
    {
      role   = "roles/storage.admin"
      member = "user:${var.gcp_owner_email}"
    },
  ]
}
