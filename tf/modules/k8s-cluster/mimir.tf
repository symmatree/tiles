resource "google_service_account" "mimir" {
  account_id   = "${var.cluster_name}-mimir"
  display_name = "${var.cluster_name} Mimir Service Account"
  description  = "Service account for ${var.cluster_name} Mimir"
  project      = var.project_id
}

resource "google_service_account_key" "mimir" {
  service_account_id = google_service_account.mimir.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

resource "onepassword_item" "gsa-mimir" {
  vault    = var.onepassword_vault
  title    = "${var.cluster_name}-gsa-mimir"
  category = "secure_note"
  section {
    label = "credentials"
    field {
      label = "credential.json"
      type  = "CONCEALED"
      value = base64decode(google_service_account_key.mimir.private_key)
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

locals {
  terraform_identity = endswith(data.google_client_openid_userinfo.terraform.email, ".iam.gserviceaccount.com") ? "serviceAccount:${data.google_client_openid_userinfo.terraform.email}" : "user:${data.google_client_openid_userinfo.terraform.email}"
}

module "mimir_encryption_key" {
  source     = "terraform-google-modules/kms/google"
  version    = ">= 4.0"
  project_id = var.project_id
  location   = var.gcp_region
  keyring    = "${var.cluster_name}-mimir"
  # Used for all the buckets
  keys               = ["mimir-storage"]
  set_decrypters_for = ["mimir-storage"]
  set_encrypters_for = ["mimir-storage"]
  set_owners_for     = ["mimir-storage"]
  decrypters = [
    "serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}",
    "serviceAccount:${google_service_account.mimir.email}",
  ]
  encrypters = [
    "serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}",
    "serviceAccount:${google_service_account.mimir.email}",
  ]
  owners = [
    local.terraform_identity
  ]
}

module "mimir_buckets" {
  source     = "terraform-google-modules/cloud-storage/google"
  version    = ">= 12.0"
  project_id = var.project_id
  location   = var.gcp_region
  names = [
    "blocks",
    "alertmanager",
    "ruler"
  ]
  prefix        = "${var.cluster_name}-mimir"
  storage_class = "STANDARD"
  versioning = {
    "blocks"       = false
    "ruler"        = true
    "alertmanager" = true
  }
  admins          = ["serviceAccount:${google_service_account.mimir.email}"]
  set_admin_roles = true
  encryption_key_names = {
    "blocks"       = module.mimir_encryption_key.keys["mimir-storage"]
    "ruler"        = module.mimir_encryption_key.keys["mimir-storage"]
    "alertmanager" = module.mimir_encryption_key.keys["mimir-storage"]
  }
  depends_on = [module.mimir_encryption_key]
}

output "mimir_bucket_chunks" {
  value = module.mimir_buckets.buckets_map["blocks"].name
}

output "mimir_bucket_alertmanager" {
  value = module.mimir_buckets.buckets_map["alertmanager"].name
}

output "mimir_bucket_ruler" {
  value = module.mimir_buckets.buckets_map["ruler"].name
}
