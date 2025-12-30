
variable "main_project_id" {
  description = "GCP project for this cluster"
  type        = string
}

variable "gcp_region" {
  description = "Google Cloud region"
  type        = string
}

variable "cluster_name" {
  description = "Cluster name"
  type        = string
}

variable "kms_project_id" {
  description = "Google Cloud KMS project ID"
  type        = string
}

variable "onepassword_vault" {
  description = "1Password vault UUID."
  type        = string
}

variable "admin_user" {
  description = "Admin user email"
  type        = string
}

data "google_storage_project_service_account" "gcs_account" {
  project = var.main_project_id
}
