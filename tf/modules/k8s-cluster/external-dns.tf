# Component: external-dns
# Documentation: charts/external-dns/README.md
# Application: charts/external-dns/application.yaml
# This module creates a Google Cloud service account and IAM bindings for external-dns to manage DNS records.

resource "google_service_account" "external_dns" {
  account_id   = "sa-${var.cluster_name}-external-dns"
  display_name = "${var.cluster_name} external-dns"
  description  = "Service account for ${var.cluster_name} external-dns to manage DNS records"
  project      = var.main_project_id
}

# Grant project-level permission to list zones (required for external-dns to discover zones)
resource "google_project_iam_member" "external_dns_dns_reader" {
  project = var.main_project_id
  role    = "roles/dns.reader"
  member  = "serviceAccount:${google_service_account.external_dns.email}"
}

# Grant zone-level permission to manage records in the public zone
resource "google_dns_managed_zone_iam_member" "external_dns_public" {
  project      = var.main_project_id
  managed_zone = module.dns-public-zone.name
  role         = "roles/dns.admin"
  member       = "serviceAccount:${google_service_account.external_dns.email}"
}

resource "google_service_account_key" "external_dns_sa_key" {
  service_account_id = google_service_account.external_dns.name
}

resource "onepassword_item" "external_dns_clouddns_sa_key" {
  vault    = var.onepassword_vault
  title    = "${var.cluster_name}-external-dns-clouddns-sa-key"
  category = "secure_note"
  section {
    label = "credentials"
    field {
      # This label is referenced in charts/external-dns/templates/clouddns-sa-secret.yaml
      label = "credential.json"
      value = base64decode(google_service_account_key.external_dns_sa_key.private_key)
      type  = "CONCEALED"
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

output "external_dns_clouddns_sa_key" {
  value     = google_service_account_key.external_dns_sa_key.private_key
  sensitive = true
}
