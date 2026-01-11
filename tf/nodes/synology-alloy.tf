# Synology Container Project for Alloy
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

# Container project configuration
# Only create in prod workspace to avoid conflicts
resource "synology_container_project" "alloy" {
  count = terraform.workspace == "prod" ? 1 : 0
  name  = "alloy"
  run   = true

  services = {
    alloy = {
      image = "grafana/alloy:latest"

      # Mount host root filesystem for node_exporter
      # Following node_exporter best practices: mount rootfs at /host
      volumes = [
        {
          type      = "bind"
          source    = "/"
          target    = "/host"
          read_only = true
          bind = {
            propagation = "rslave"
          }
        },
      ]

      # Mount Alloy configuration file as a config
      configs = [
        {
          source = "alloy_config"
          target = "/etc/alloy/config.alloy"
        }
      ]

      # Environment variables
      environment = {
        HOSTNAME = "raconteur"
      }

      # Network and PID mode - required for node_exporter
      network_mode = "host"
      pid          = "host"

      # Resource limits
      mem_limit = "512M"

      # Restart policy
      restart = "unless-stopped"
    }
  }

  # Alloy configuration file as a config
  configs = {
    alloy_config = {
      name = "alloy_config"
      content = templatefile("${path.root}/templates/alloy-synology.alloy", {
        otlp_tiles_test = "https://otlp.tiles-test.symmatree.com"
        otlp_tiles      = "https://otlp.tiles.symmatree.com"
      })
    }
  }
}
