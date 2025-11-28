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

# Create NS records in Cloudflare to delegate the subdomain to Google Cloud DNS
resource "cloudflare_dns_record" "delegation" {
  count = length(module.dns-public-zone.name_servers)

  zone_id = data.cloudflare_zone.parent_zone.id
  name    = var.cluster_name
  type    = "NS"
  ttl     = 300
  content = trimsuffix(module.dns-public-zone.name_servers[count.index], ".")
  comment = "Managed by Terraform"
}
