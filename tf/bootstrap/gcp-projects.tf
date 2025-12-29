# GCP Enterprise Foundation Projects
# Reference: https://docs.cloud.google.com/architecture/blueprints/security-foundations

variable "gcp_essential_contacts_email" {
  description = "Email address for essential contacts on GCP projects"
  type        = string
}

# Get billing account from the seed project
data "google_project" "seed" {
  project_id = var.gcp_project_id
}

# Workload Identity Project
module "tiles_id_project" {
  source  = "terraform-google-modules/project-factory/google"
  version = ">= 17.0"

  name              = "tiles-id"
  random_project_id = true
  org_id            = null
  billing_account   = data.google_project.seed.billing_account
  folder_id         = null

  labels = {
    tiles       = "true"
    environment = "shared"
  }

  activate_apis = [
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "essentialcontacts.googleapis.com",
  ]

  budget_amount                           = 10
  budget_alert_pubsub_topic               = null
  budget_alert_spent_percents             = [0.5, 1.0]
  budget_monitoring_notification_channels = []
}

# Grant Owner role to tiles-owner group on tiles-id project
resource "google_project_iam_member" "tiles_id_owner" {
  project = module.tiles_id_project.project_id
  role    = "roles/owner"
  member  = "group:tiles-owner@googlegroups.com"
}

# Set essential contacts for tiles-id project
resource "google_essential_contacts_contact" "tiles_id_contact" {
  parent                              = "projects/${module.tiles_id_project.project_id}"
  email                               = var.gcp_essential_contacts_email
  language_tag                        = "en"
  notification_category_subscriptions = ["ALL"]
}

# KMS Project for centralized secrets
module "tiles_kms_project" {
  source  = "terraform-google-modules/project-factory/google"
  version = ">= 17.0"

  name              = "tiles-kms"
  random_project_id = true
  org_id            = null
  billing_account   = data.google_project.seed.billing_account
  folder_id         = null

  labels = {
    tiles       = "true"
    environment = "shared"
  }

  activate_apis = [
    "cloudresourcemanager.googleapis.com",
    "cloudkms.googleapis.com",
    "essentialcontacts.googleapis.com",
  ]

  budget_amount                           = 10
  budget_alert_pubsub_topic               = null
  budget_alert_spent_percents             = [0.5, 1.0]
  budget_monitoring_notification_channels = []
}

# Grant Owner role to tiles-owner group on tiles-kms project
resource "google_project_iam_member" "tiles_kms_owner" {
  project = module.tiles_kms_project.project_id
  role    = "roles/owner"
  member  = "group:tiles-owner@googlegroups.com"
}

# Set essential contacts for tiles-kms project
resource "google_essential_contacts_contact" "tiles_kms_contact" {
  parent                              = "projects/${module.tiles_kms_project.project_id}"
  email                               = var.gcp_essential_contacts_email
  language_tag                        = "en"
  notification_category_subscriptions = ["ALL"]
}

# Per-environment project for tiles (prod)
module "tiles_main_project" {
  source  = "terraform-google-modules/project-factory/google"
  version = ">= 17.0"

  name              = "tiles-main"
  random_project_id = true
  org_id            = null
  billing_account   = data.google_project.seed.billing_account
  folder_id         = null

  labels = {
    tiles       = "true"
    environment = "prod"
  }

  activate_apis = [
    "cloudresourcemanager.googleapis.com",
    "storage.googleapis.com",
    "dns.googleapis.com",
    "iam.googleapis.com",
    "essentialcontacts.googleapis.com",
  ]

  budget_amount                           = 10
  budget_alert_pubsub_topic               = null
  budget_alert_spent_percents             = [0.5, 1.0]
  budget_monitoring_notification_channels = []
}

# Grant Owner role to tiles-owner group on tiles-main project
resource "google_project_iam_member" "tiles_main_owner" {
  project = module.tiles_main_project.project_id
  role    = "roles/owner"
  member  = "group:tiles-owner@googlegroups.com"
}

# Set essential contacts for tiles-main project
resource "google_essential_contacts_contact" "tiles_main_contact" {
  parent                              = "projects/${module.tiles_main_project.project_id}"
  email                               = var.gcp_essential_contacts_email
  language_tag                        = "en"
  notification_category_subscriptions = ["ALL"]
}

# Per-environment project for tiles-test
module "tiles_test_main_project" {
  source  = "terraform-google-modules/project-factory/google"
  version = ">= 17.0"

  name              = "tiles-test-main"
  random_project_id = true
  org_id            = null
  billing_account   = data.google_project.seed.billing_account
  folder_id         = null

  labels = {
    tiles       = "true"
    environment = "test"
  }

  activate_apis = [
    "cloudresourcemanager.googleapis.com",
    "storage.googleapis.com",
    "dns.googleapis.com",
    "iam.googleapis.com",
    "essentialcontacts.googleapis.com",
  ]

  budget_amount                           = 10
  budget_alert_pubsub_topic               = null
  budget_alert_spent_percents             = [0.5, 1.0]
  budget_monitoring_notification_channels = []
}

# Grant Owner role to tiles-owner group on tiles-test-main project
resource "google_project_iam_member" "tiles_test_main_owner" {
  project = module.tiles_test_main_project.project_id
  role    = "roles/owner"
  member  = "group:tiles-owner@googlegroups.com"
}

# Set essential contacts for tiles-test-main project
resource "google_essential_contacts_contact" "tiles_test_main_contact" {
  parent                              = "projects/${module.tiles_test_main_project.project_id}"
  email                               = var.gcp_essential_contacts_email
  language_tag                        = "en"
  notification_category_subscriptions = ["ALL"]
}

# Outputs for created projects
output "tiles_id_project_id" {
  description = "Project ID for the tiles-id workload identity project"
  value       = module.tiles_id_project.project_id
}

output "tiles_kms_project_id" {
  description = "Project ID for the tiles-kms centralized secrets project"
  value       = module.tiles_kms_project.project_id
}

output "tiles_main_project_id" {
  description = "Project ID for the tiles-main prod environment project"
  value       = module.tiles_main_project.project_id
}

output "tiles_test_main_project_id" {
  description = "Project ID for the tiles-test-main test environment project"
  value       = module.tiles_test_main_project.project_id
}
