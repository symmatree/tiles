# Synology Container Project for Alloy
# This creates a container project on the Synology NAS running Alloy
# to collect metrics and logs from the Synology host
#
# NOTE: The resource types (synology_container_project, synology_file) are placeholders
# and may need to be adjusted based on the actual Synology provider API.
# The Synology provider may use different resource names or structures.
# Please refer to the provider documentation for the correct resource types.

variable "synology_host" {
  description = "Synology DSM hostname or IP address"
  type        = string
  default     = "raconteur.ad.local.symmatree.com"
}

# Container project configuration
# Note: Resource type may vary - check provider documentation
# Only create in prod workspace to avoid conflicts
resource "synology_container_project" "alloy" {
  count       = terraform.workspace == "prod" ? 1 : 0
  name        = "alloy"
  description = "Alloy telemetry collector for Synology host metrics and logs"

  # Container configuration
  container {
    name  = "alloy"
    image = "grafana/alloy:latest"

    # Mount host volumes for logs and system information
    volume {
      source      = "/var/log"
      destination = "/host/var/log"
      type        = "bind"
      read_only   = true
    }

    volume {
      source      = "/proc"
      destination = "/host/proc"
      type        = "bind"
      read_only   = true
    }

    volume {
      source      = "/sys"
      destination = "/host/sys"
      type        = "bind"
      read_only   = true
    }

    volume {
      source      = "/run"
      destination = "/host/run"
      type        = "bind"
      read_only   = true
    }

    volume {
      source      = "/etc"
      destination = "/host/etc"
      type        = "bind"
      read_only   = true
    }

    # Alloy configuration file
    volume {
      source      = "/volume1/docker/alloy/config.alloy"
      destination = "/etc/alloy/config.alloy"
      type        = "bind"
      read_only   = true
    }

    # Environment variables
    env = {
      HOSTNAME = "raconteur"
    }

    # Network mode - use host network to access host metrics
    network_mode = "host"

    # Resource limits
    resources {
      cpu_limit    = "2"
      memory_limit = "512M"
    }

    # Restart policy
    restart_policy = "unless-stopped"
  }
}

# Alloy configuration file
# Note: The exact resource type may vary depending on the Synology provider implementation
# This may need to be adjusted to match the actual provider API
# Only create in prod workspace to avoid conflicts
resource "synology_file" "alloy_config" {
  count = terraform.workspace == "prod" ? 1 : 0
  path  = "/volume1/docker/alloy/config.alloy"
  content = templatefile("${path.root}/templates/alloy-synology.alloy", {
    otlp_tiles_test = "https://otlp.tiles-test.symmatree.com"
    otlp_tiles      = "https://otlp.tiles.symmatree.com"
  })
  permissions = "0644"
}
