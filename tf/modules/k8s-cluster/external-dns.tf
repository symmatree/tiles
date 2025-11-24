resource "google_service_account" "external_dns" {
  account_id   = "sa-${var.cluster_name}-external-dns"
  display_name = "${var.cluster_name} external-dns"
  description  = "Service account for ${var.cluster_name} external-dns to manage DNS records"
  project      = var.project_id
}

resource "google_dns_managed_zone_iam_member" "external_dns_public" {
  project      = var.project_id
  managed_zone = module.dns-public-zone.name
  role         = "roles/dns.admin"
  member       = "serviceAccount:${google_service_account.external_dns.email}"
}

resource "google_service_account_key" "external_dns_sa_key" {
  service_account_id = google_service_account.external_dns.name
}

resource "onepassword_item" "external_dns_clouddns_sa_key" {
  vault      = var.onepassword_vault
  title      = "${var.cluster_name}-external-dns-clouddns-sa-key"
  category   = "secure_note"
  section {
    label = "credentials"
    field {
      # This label is referenced in charts/external-dns/templates/clouddns-sa-secret.yaml
      label = "credential.json"
      value = base64decode(google_service_account_key.external_dns_sa_key.private_key)
      type = "CONCEALED"
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
  value = google_service_account_key.external_dns_sa_key.private_key
  sensitive = true
}
