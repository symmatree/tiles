# Component: NTRIP / RTKBase on acebase (prod only)
# Documentation: tanka/environments/ntrip/README.md
# Application: tanka/environments/ntrip/application.yaml

resource "onepassword_item" "ntrip_caster_auth" {
  count    = var.cluster_name == "tiles" ? 1 : 0
  vault    = var.onepassword_vault
  title    = "${var.cluster_name}-ntrip-caster-auth"
  category = "login"
  username = "gps"
  password = "gps"
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
