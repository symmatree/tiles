
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

variable "seed_project_id" {
  description = "GCP seed project ID (symm-custodes) where shared DNS zones are located"
  type        = string
}

variable "dns_zone_ad_local" {
  description = "DNS zone name for ad.local.symmatree.com in seed project"
  type        = string
}

variable "dns_zone_local" {
  description = "DNS zone name for local.symmatree.com in seed project"
  type        = string
}

data "google_storage_project_service_account" "gcs_account" {
  project = var.main_project_id
}
