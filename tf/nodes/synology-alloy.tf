# Synology Container Project for Alloy
# Documentation: docs/synology-monitoring.md
# This creates a container project on the Synology NAS running Alloy
# to collect metrics and logs from the Synology host
#
# NOTE: The resource types (synology_container_project, synology_file) are placeholders
# and may need to be adjusted based on the actual Synology provider API.
# The Synology provider may use different resource names or structures.
# Please refer to the provider documentation for the correct resource types.

variable "synology_host" {
  description = "Synology DSM hostname or IP address with protocol and port (e.g., https://raconteur.ad.local.symmatree.com:5001)"
  type        = string
}

# Fetch SNMP credentials from 1Password
data "onepassword_item" "raconteur_snmp" {
  vault = data.onepassword_vault.tf_secrets.uuid
  title = "raconteur-snmp"
}

module "raconteur_snmp_privacy_password" {
  source = "../modules/onepassword_field"

  vault_name   = var.onepassword_vault_name
  item_name    = "raconteur-snmp"
  section_name = "privacy"
  field_name   = "PRIVACY_PASSWORD"
}

# Container project configuration
# Unique; run in sbox while iterating and then prod later.
resource "synology_container_project" "alloy" {
  count = terraform.workspace == "test" ? 1 : 0
  name  = "alloy"
  run   = true

  services = {
    alloy = {
      image = "grafana/alloy:latest"

      # Mount host root filesystem for node_exporter
      # Using simple bind mount without propagation to avoid Synology error:
      # "path / is mounted on / but it is not a shared or a slave mount"
      #
      # Tradeoff: Existing sub-mounts (like /proc, /sys) will be visible,
      # but new mounts added to the host after container start won't appear.
      # This is acceptable for Synology NAS where mounts are relatively static.
      volumes = [
        {
          type      = "bind"
          source    = "/"
          target    = "/host"
          read_only = true
        },
      ]

      # Mount Alloy configuration file as a config
      configs = [
        {
          source = "alloy_config"
          target = "/etc/alloy/config.alloy"
        },
        {
          source = "snmp_config"
          target = "/etc/snmp_exporter/snmp.yml"
        }
      ]

      # Command-line arguments
      # Enable Alloy UI on 0.0.0.0:12345 (default is localhost:12345)
      command = [
        "run",
        "--server.http.listen-addr=0.0.0.0:12345",
        "/etc/alloy/config.alloy"
      ]

      # Environment variables
      environment = {
        HOSTNAME = "raconteur"
      }

      # Network and PID mode - required for node_exporter
      network_mode = "host"
      pid          = "host"

      # Ports (with host networking, these are directly on the host)
      ports = [{
        target    = 12345
        published = "12345"
      }]

      # Resource limits
      mem_limit = "512M"

      # Restart policy
      restart = "unless-stopped"
    }
  }

  # Configuration files
  configs = {
    alloy_config = {
      name = "alloy_config"
      content = templatefile("${path.root}/templates/alloy-synology.alloy", {
        otlp_tiles_test = "https://otlp.tiles-test.symmatree.com"
        otlp_tiles      = "https://otlp.tiles.symmatree.com"
      })
    }
    snmp_config = {
      name = "snmp_config"
      content = templatefile("${path.root}/templates/snmp-synology.yml", {
        snmp_username      = data.onepassword_item.raconteur_snmp.username
        snmp_auth_password = data.onepassword_item.raconteur_snmp.password
        snmp_priv_password = module.raconteur_snmp_privacy_password.field_value
      })
    }
  }
}
