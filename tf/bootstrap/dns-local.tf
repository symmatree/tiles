# Records in the shared local.symmatree.com zone (seed project).
#
# The zone itself is not managed here: cert-manager writes and removes
# _acme-challenge TXT records in it for DNS-01, so nothing may own the zone as a
# whole. Only the individual records below are declared.
#
# Forward names under local.symmatree.com are normally served by UniFi from its
# DHCP table, which is why hosts like morpheus are absent from this zone. These
# two are the exception: they are CNAMEs onto the Synology, which UniFi cannot
# serve, so they have to live in the public zone.

variable "dns_zone_local" {
  description = "Cloud DNS managed-zone name for local.symmatree.com in the seed project"
  type        = string
}

resource "google_dns_record_set" "cam" {
  project      = var.seed_project_id
  managed_zone = var.dns_zone_local
  name         = "cam.local.symmatree.com."
  type         = "CNAME"
  ttl          = 300
  rrdatas      = ["raconteur.ad.local.symmatree.com."]
}

resource "google_dns_record_set" "photos" {
  project      = var.seed_project_id
  managed_zone = var.dns_zone_local
  name         = "photos.local.symmatree.com."
  type         = "CNAME"
  ttl          = 300
  rrdatas      = ["raconteur.ad.local.symmatree.com."]
}
