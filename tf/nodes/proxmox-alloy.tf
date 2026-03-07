# Proxmox LXC Container for Alloy
# Documentation: docs/proxmox-monitoring.md (to be created)
# This creates an LXC container on each Proxmox node running Alloy
# to collect metrics and logs from the Proxmox host
#
# Similar to synology-alloy.tf but for Proxmox LXC containers
#
# VM/CT IDs are unique cluster-wide in Proxmox, so we assign one per node (200, 201, ...).
# When deploy_proxmox_alloy is false, no containers/OCI/images/snippets are created.
locals {
  alloy_nodes  = var.deploy_proxmox_alloy ? toset(data.proxmox_virtual_environment_nodes.nodes.names) : toset([])
  alloy_vm_ids = { for i, n in sort(tolist(local.alloy_nodes)) : n => var.alloy_vm_base_id + i }
}

# Pull Alloy OCI image on each Proxmox node
resource "proxmox_virtual_environment_oci_image" "alloy" {
  for_each = local.alloy_nodes

  node_name    = each.value
  datastore_id = "local"
  reference    = "docker.io/grafana/alloy:latest"
}

# Deploy to all Proxmox nodes
# Using proxmox_root provider for bind mounts (requires root@pam)
resource "proxmox_virtual_environment_container" "alloy" {
  for_each   = local.alloy_nodes
  provider   = proxmox.proxmox_root
  depends_on = [proxmox_virtual_environment_file.alloy_config]

  node_name = each.value
  vm_id     = local.alloy_vm_ids[each.key]

  # Use OCI image - grafana/alloy:latest (same as Synology setup)
  operating_system {
    # ubuntu is underlying: https://github.com/grafana/alloy/blob/main/Dockerfile#L41
    type             = "ubuntu"
    template_file_id = proxmox_virtual_environment_oci_image.alloy[each.value].id
  }
  environment_variables = {
    ALLOY_DEPLOY_MODE = "docker"
    PATH              = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  }

  # Initialization
  initialization {
    hostname = "alloy-${each.value}"
    # Default from container does not have the listen-addr set.
    entrypoint = "/bin/alloy run /var/lib/vz/snippets/alloy-proxmox.alloy '--storage.path=/var/lib/alloy/data' '--server.http.listen-addr=0.0.0.0:12345'"
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  # Disk for container
  disk {
    mount_options = []
    datastore_id  = "local-lvm"
  }

  # Network - bridge to vmbr0 (adjust if your network setup differs)
  network_interface {
    firewall = true
    name     = "eth0"
    bridge   = "vmbr0"
  }
  console {
    enabled   = true
    tty_count = 2
    type      = "console"
  }

  # Privileged required so bind mount of host / at /host exposes readable /host/proc and /host/sys for node_exporter.
  unprivileged = false
  memory {
    dedicated = 512
  }

  # Mount host root filesystem (read-only for safety)
  # This gives access to /sys, /proc, /dev, /run from the host
  # Same approach as Synology - bind mount host root to /host
  mount_point {
    path          = "/host"
    read_only     = true
    mount_options = []
    volume        = "/"
  }
  # Snippets dir bind mount at same path as host so we leave image /etc/alloy untouched (avoid unpack/permission issues).
  mount_point {
    path          = "/var/lib/vz/snippets"
    read_only     = true
    mount_options = []
    volume        = "/var/lib/vz/snippets"
  }
  # Start on boot
  start_on_boot = true

  # Tags for identification
  tags = ["alloy", "monitoring"]

  # Notes
  description = "Alloy monitoring container for ${each.value} - collects host metrics and logs via node_exporter (hwmon sensors) and system logs"
}

# Upload Alloy config file as a snippet (mounted into container at /var/lib/vz/snippets/alloy-proxmox.alloy)
resource "proxmox_virtual_environment_file" "alloy_config" {
  for_each = local.alloy_nodes
  provider = proxmox.proxmox_root

  node_name    = each.value
  datastore_id = "local"
  content_type = "snippets"
  source_raw {
    data = templatefile("${path.root}/templates/alloy-proxmox.alloy", {
      otlp_tiles_test = "https://otlp.tiles-test.symmatree.com"
      otlp_tiles      = "https://otlp.tiles.symmatree.com"
      hostname        = each.value
    })
    file_name = "alloy-proxmox.alloy"
  }
}
