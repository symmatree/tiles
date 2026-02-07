# Proxmox LXC Container for Alloy
# Documentation: docs/proxmox-monitoring.md (to be created)
# This creates an LXC container on each Proxmox node running Alloy
# to collect metrics and logs from the Proxmox host
#
# Similar to synology-alloy.tf but for Proxmox LXC containers

# Pull Alloy OCI image on each Proxmox node
resource "proxmox_virtual_environment_oci_image" "alloy" {
  for_each = toset(data.proxmox_virtual_environment_nodes.nodes.names)

  node_name    = each.value
  datastore_id = "local"
  reference    = "docker.io/grafana/alloy:latest"
}

# Deploy to all Proxmox nodes
# Using proxmox_root provider for bind mounts (requires root@pam)
resource "proxmox_virtual_environment_container" "alloy" {
  for_each = toset(data.proxmox_virtual_environment_nodes.nodes.names)
  provider = proxmox.proxmox_root

  node_name = each.value
  vm_id     = 200 # Fixed VM ID for alloy containers across all nodes

  # Use OCI image - grafana/alloy:latest (same as Synology setup)
  operating_system {
    # ubuntu is underlying: https://github.com/grafana/alloy/blob/main/Dockerfile#L41
    type            = "ubuntu"
    template_file_id = proxmox_virtual_environment_oci_image.alloy[each.value].id
  }

  # Initialization
  initialization {
    hostname = "alloy-${each.value}"

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  # Disk for container
  disk { datastore_id = "local-lvm" }

  # Network - bridge to vmbr0 (adjust if your network setup differs)
  network_interface {
    name   = "net0"
    bridge = "vmbr0"
  }

#   # Privileged mode required for accessing host /sys, /proc, etc.
#   # This allows the container to see host filesystems and hardware sensors
# privileged = true

  # Mount host root filesystem (read-only for safety)
  # This gives access to /sys, /proc, /dev, /run from the host
  # Same approach as Synology - bind mount host root to /host
  mount_point {
    path = "/host"
    read_only = true
    volume = "/"
  }

#   # Mount Alloy config file from snippet
#   mount_point {
#     key     = "1"
#     slot    = 1
#     storage = "local"
#     volume  = "snippets/alloy-proxmox-${each.value}.alloy"
#     mp      = "/etc/alloy/config.alloy"
#     options = "ro"
#   }

  # Start on boot
  start_on_boot = true

  # Tags for identification
  tags = ["alloy", "monitoring"]

  # Notes
  description = "Alloy monitoring container for ${each.value} - collects host metrics and logs via node_exporter (hwmon sensors) and system logs"
}

# Upload Alloy config file as a snippet (mounted into container)
resource "proxmox_virtual_environment_file" "alloy_config" {
  for_each = toset(data.proxmox_virtual_environment_nodes.nodes.names)

  node_name    = each.value
  datastore_id = "local"
  content_type = "snippets"
  source_raw {
    data = templatefile("${path.root}/templates/alloy-proxmox.alloy", {
      otlp_tiles_test = "https://otlp.tiles-test.symmatree.com"
      otlp_tiles      = "https://otlp.tiles.symmatree.com"
      hostname        = each.value
    })
    file_name = "alloy-proxmox-${each.value}.alloy"
  }
}

# NOTE: Container args/command may need to be set manually or via hookscript if provider doesn't support it:
#    pct set {vm_id} --args "run --server.http.listen-addr=0.0.0.0:12345 /etc/alloy/config.alloy"
#
# The Alloy image's default entrypoint should be the alloy binary, so args should work
