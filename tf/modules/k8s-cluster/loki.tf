# Component: Loki
# Documentation: charts/loki/README.md
# Application: charts/loki/application.yaml
# This module creates Google Cloud service accounts, KMS keys, and GCS buckets for Loki log storage.

resource "google_service_account" "loki" {
  account_id   = "${var.cluster_name}-loki"
  display_name = "${var.cluster_name} Loki Service Account"
  description  = "Service account for ${var.cluster_name} Loki"
  project      = var.project_id
}

resource "google_service_account_key" "loki" {
  service_account_id = google_service_account.loki.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

resource "onepassword_item" "gsa-loki" {
  vault    = var.onepassword_vault
  title    = "${var.cluster_name}-gsa-loki"
  category = "secure_note"
  section {
    label = "credentials"
    field {
      label = "credential.json"
      type  = "CONCEALED"
      value = base64decode(google_service_account_key.loki.private_key)
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

resource "random_password" "loki_cluster_tenant" {
  length  = 24
  special = true
}

resource "htpasswd_password" "loki_cluster_tenant" {
  password = random_password.loki_cluster_tenant.result
}

resource "htpasswd_password" "loki_self_monitoring" {
  # No real need for a password for this tenant.
  password = ""
}


resource "onepassword_item" "loki_tenant_auth_secret" {
  vault    = var.onepassword_vault
  title    = "${var.cluster_name}-loki-tenant-auth"
  category = "secure_note"
  section {
    label = "credentials"
    field {
      label = "username"
      value = var.cluster_name
    }
    field {
      label = "password"
      type  = "CONCEALED"
      value = random_password.loki_cluster_tenant.result
    }
    field {
      label = "tenantId"
      value = var.cluster_name
    }
    field {
      label = ".htpasswd"
      type  = "CONCEALED"
      value = <<-EOT
        ${var.cluster_name}:${htpasswd_password.loki_cluster_tenant.bcrypt}
        self-monitoring:${htpasswd_password.loki_self_monitoring.bcrypt}
EOT
    }
    field {
      label = "datasource.yaml"
      value = <<-EOT
apiVersion: 1
datasources:
  - name: Loki
    uid: loki
    type: loki
    url: http://loki-gateway.loki.svc
    isDefault: false
    jsonData:
      httpHeaderName1: X-Scope-OrgID
      basicAuth: true
    secureJsonData:
      httpHeaderValue1: ${var.cluster_name}
      basicAuthUser: ${var.cluster_name}
      basicAuthPassword: ${random_password.loki_cluster_tenant.result}
EOT
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
  admin_identity = "user:${var.admin_user}"
}

module "loki_encryption_key" {
  source     = "terraform-google-modules/kms/google"
  version    = ">= 4.0"
  project_id = var.project_id
  location   = var.gcp_region
  keyring    = "${var.cluster_name}-loki"
  # Used for all the buckets
  keys               = ["loki-storage"]
  set_decrypters_for = ["loki-storage"]
  set_encrypters_for = ["loki-storage"]
  set_owners_for     = ["loki-storage"]
  decrypters = [
    "serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}",
    "serviceAccount:${google_service_account.loki.email}",
  ]
  encrypters = [
    "serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}",
    "serviceAccount:${google_service_account.loki.email}",
  ]
  owners = [
    local.admin_identity
  ]
}

module "loki_buckets" {
  source     = "terraform-google-modules/cloud-storage/google"
  version    = ">= 12.0"
  project_id = var.project_id
  location   = var.gcp_region
  names = [
    "chunks",
    "ruler",
    "admin"
  ]
  prefix        = "${var.cluster_name}-loki"
  storage_class = "STANDARD"
  versioning = {
    "chunks" = false
    "ruler"  = true
    "admin"  = true
  }
  admins          = ["serviceAccount:${google_service_account.loki.email}"]
  set_admin_roles = true
  encryption_key_names = {
    "chunks" = module.loki_encryption_key.keys["loki-storage"]
    "ruler"  = module.loki_encryption_key.keys["loki-storage"]
    "admin"  = module.loki_encryption_key.keys["loki-storage"]
  }
  depends_on = [module.loki_encryption_key]
}

output "loki_bucket_chunks" {
  value = module.loki_buckets.buckets_map["chunks"].name
}

output "loki_bucket_ruler" {
  value = module.loki_buckets.buckets_map["ruler"].name
}

output "loki_bucket_admin" {
  value = module.loki_buckets.buckets_map["admin"].name
}
