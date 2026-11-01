# versitygw: an S3 endpoint served from Raconteur, storing objects as plain files
# on the NAS's own btrfs volume (not over NFS). Trial deployment against an empty
# directory; Mimir is not pointed at it yet.
#
# TLS terminates in versitygw with the Let's Encrypt certificate that
# charts/static-certs issues for raconteur.ad.local.symmatree.com, read here from
# the cluster. Renewals reach the container on the next apply (daily schedule).

locals {
  versitygw_endpoint = "https://raconteur.ad.local.symmatree.com:7070"
}

data "kubernetes_secret_v1" "raconteur_cert" {
  count = var.deploy_synology_versitygw ? 1 : 0
  metadata {
    name      = "raconteur-cert"
    namespace = "static-certs"
  }
}

resource "random_password" "versitygw_root" {
  count   = var.deploy_synology_versitygw ? 1 : 0
  length  = 40
  special = false
  # Bumped to rotate the root secret.
  keepers = {
    generation = 2
  }
}

resource "onepassword_item" "versitygw_root" {
  count    = var.deploy_synology_versitygw ? 1 : 0
  vault    = data.onepassword_vault.tf_secrets.uuid
  title    = "versitygw-root"
  category = "login"
  username = "versitygw-root"
  url      = local.versitygw_endpoint
  password = random_password.versitygw_root[0].result
}

# Object data; each top-level directory is a bucket.
resource "synology_filestation_folder" "versitygw_trial" {
  count = var.deploy_synology_versitygw ? 1 : 0
  path  = "/tiles/s3-trial"
}

# Internal IAM accounts, kept outside the data root so they are not a bucket.
resource "synology_filestation_folder" "versitygw_iam" {
  count = var.deploy_synology_versitygw ? 1 : 0
  path  = "/tiles/versitygw-iam"
}

resource "synology_container_project" "versitygw" {
  count = var.deploy_synology_versitygw ? 1 : 0
  name  = "versitygw"
  run   = true

  # Paths are written out (not the folders' real_path, which is unknown at plan
  # time) so the rendered compose content is fully known when planned.
  depends_on = [synology_filestation_folder.versitygw_trial, synology_filestation_folder.versitygw_iam]

  services = {
    versitygw = {
      image = "versity/versitygw:v1.10.0"

      # The root secret is a compose secret, not an environment value: the provider
      # renders services into the project's compose content, which is not marked
      # sensitive and is printed in full when an apply fails.
      entrypoint = [
        "/bin/sh", "-c",
        # $$ is compose's escape for a literal $.
        "export ROOT_SECRET_ACCESS_KEY=\"$$(cat /run/secrets/root_secret)\"; exec /usr/local/bin/versitygw \"$$@\"",
        "versitygw",
      ]

      command = [
        "--port", ":7070",
        "--cert", "/certs/tls.crt",
        "--key", "/certs/tls.key",
        "--iam-dir", "/iam",
        "posix", "/data",
      ]

      environment = {
        ROOT_ACCESS_KEY_ID = "versitygw-root"
      }

      secrets = [{
        source = "root_secret"
        target = "/run/secrets/root_secret"
      }]

      volumes = [
        {
          type   = "bind"
          source = "${var.cluster_nfs_path}/s3-trial"
          target = "/data"
        },
        {
          type   = "bind"
          source = "${var.cluster_nfs_path}/versitygw-iam"
          target = "/iam"
        },
      ]

      configs = [
        {
          source = "tls_crt"
          target = "/certs/tls.crt"
        },
        {
          source = "tls_key"
          target = "/certs/tls.key"
        },
      ]

      ports = [{
        target    = 7070
        published = "7070"
      }]

      mem_limit = "512M"
      restart   = "unless-stopped"
    }
  }

  secrets = {
    root_secret = {
      name    = "root_secret"
      content = random_password.versitygw_root[0].result
    }
  }

  configs = {
    tls_crt = {
      name    = "tls_crt"
      content = data.kubernetes_secret_v1.raconteur_cert[0].data["tls.crt"]
    }
    tls_key = {
      name    = "tls_key"
      content = data.kubernetes_secret_v1.raconteur_cert[0].data["tls.key"]
    }
  }
}
