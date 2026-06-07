# Component: NTRIP / RTKBase on acebase (prod only)
# Documentation: tanka/environments/ntrip/README.md
# Application: tanka/environments/ntrip/application.yaml

resource "random_password" "ntrip_admin" {
  count   = var.cluster_name == "tiles" ? 1 : 0
  length  = 24
  special = false
}

resource "onepassword_item" "ntrip_admin" {
  count    = var.cluster_name == "tiles" ? 1 : 0
  vault    = var.onepassword_vault
  title    = "${var.cluster_name}-ntrip-admin"
  category = "login"
  username = "admin"
  password = random_password.ntrip_admin[0].result
  url      = "https://ntrip-admin.tiles.symmatree.com"

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

resource "random_password" "ntrip_caster" {
  count   = var.cluster_name == "tiles" ? 1 : 0
  length  = 24
  special = false
}

resource "onepassword_item" "ntrip_caster_auth" {
  count    = var.cluster_name == "tiles" ? 1 : 0
  vault    = var.onepassword_vault
  title    = "${var.cluster_name}-ntrip-caster-auth"
  category = "login"
  username = "gps"
  password = random_password.ntrip_caster[0].result
  url      = "ntrip://ntrip.tiles.symmatree.com:2101/ATTIC"

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
