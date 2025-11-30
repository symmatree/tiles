locals {
  fqdn = "${var.cluster_name}.symmatree.com"
}

module "dns-public-zone" {
  source  = "terraform-google-modules/cloud-dns/google"
  version = "~> 6.0"

  project_id = var.project_id
  type       = "public"
  name       = var.cluster_name
  domain     = "${local.fqdn}."
  labels = {
    name    = var.cluster_name
    cluster = var.cluster_name
  }

  recordsets = [
    {
      name = "ns"
      type = "A"
      ttl  = 300
      records = [
        "127.0.0.1",
      ]
    },
    {
      name = ""
      type = "NS"
      ttl  = 300
      records = [
        "ns.${local.fqdn}.",
      ]
    },
    {
      name = "localhost"
      type = "A"
      ttl  = 300
      records = [
        "127.0.0.1",
      ]
    }
  ]
}

# Get the Cloudflare zone for symmatree.com
data "cloudflare_zone" "parent_zone" {
  filter = {
    name = "symmatree.com"
  }
}

# Validate that Google Cloud DNS public zone has exactly 4 name servers
check "name_servers_count" {
  assert {
    condition     = length(module.dns-public-zone.name_servers) == 4
    error_message = "Expected 4 name servers from Google Cloud DNS, but got ${length(module.dns-public-zone.name_servers)}"
  }
}

# Create NS records in Cloudflare to delegate the subdomain to Google Cloud DNS
# Google Cloud DNS public zones always have 4 name servers
resource "cloudflare_dns_record" "delegation" {
  count = 4

  zone_id = data.cloudflare_zone.parent_zone.id
  name    = var.cluster_name
  type    = "NS"
  ttl     = 300
  content = trimsuffix(module.dns-public-zone.name_servers[count.index], ".")
  comment = "Managed by Terraform"
}
