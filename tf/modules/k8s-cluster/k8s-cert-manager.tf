resource "google_service_account" "cert_manager_dns01" {
  account_id   = "sa-${var.cluster_name}-cert-manager-dns01"
  display_name = "${var.cluster_name} cert-manager DNS01 Solver"
  description  = "Service account for ${var.cluster_name} cert-manager to perform DNS01 ACME challenges"
  project      = var.project_id
}

resource "google_dns_managed_zone_iam_member" "cert_manager_dns01_public" {
  project      = var.project_id
  managed_zone = module.dns-public-zone.name
  role         = "roles/dns.admin"
  member       = "serviceAccount:${google_service_account.cert_manager_dns01.email}"
}

resource "google_service_account_key" "cert_manager_dns01_sa_key" {
  service_account_id = google_service_account.cert_manager_dns01.name
}

resource "onepassword_item" "cert_manager_dns01_sa_key" {
  vault      = var.onepassword_vault
  title      = "${var.cluster_name}-cert-manager-dns01-sa-key"
  category   = "secure_note"
  section {
    label = "credentials"
    field {
      # This label is referenced in charts/cert-manager/templates/lets-encrypt-issuers.yaml
      label = "private_key.json"
      value = base64decode(google_service_account_key.cert_manager_dns01_sa_key.private_key)
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

output "cert_manager_dns01_sa_key" {
  value = google_service_account_key.cert_manager_dns01_sa_key.private_key
  sensitive = true
}
