# Proxmox LXC Container for Alloy
# Documentation: docs/proxmox-monitoring.md
# This creates an LXC container on each Proxmox node running Alloy
# to collect metrics and logs from the Proxmox host
#
# Similar to synology-alloy.tf but for Proxmox LXC containers
#
# VM/CT IDs are unique cluster-wide in Proxmox, so we assign one per node (200, 201, ...).
# When deploy_proxmox_alloy is false, no containers/OCI/images/snippets are created.
#
# Operational note: config is delivered as the snippet config.alloy bind-mounted at /etc/alloy, and
# loaded by the image's default entrypoint (no override -- see the initialization block, #695). A
# config-content change updates the snippet but a running CT keeps the old file open until restarted;
# mount/network changes are ForceNew and recreate the CT. Stop/restart (or recreate) to pick up changes.
locals {
  alloy_nodes  = var.deploy_proxmox_alloy ? toset(data.proxmox_virtual_environment_nodes.nodes.names) : toset([])
  alloy_vm_ids = { for i, n in sort(tolist(local.alloy_nodes)) : n => var.alloy_vm_base_id + i }
}

# Pull Alloy OCI image on each Proxmox node
resource "proxmox_oci_image" "alloy" {
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
    template_file_id = proxmox_oci_image.alloy[each.value].id
  }
  environment_variables = {
    ALLOY_DEPLOY_MODE = "docker"
    PATH              = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  }

  # Initialization
  # NOTE: no `entrypoint` override. The bpg provider does not reliably apply
  # initialization settings (entrypoint, env vars) to OCI-image containers on create
  # (bpg/terraform-provider-proxmox#2789), so an overridden entrypoint gets silently
  # dropped on (re)create and the CT falls back to the image default -- which loads the
  # image's demo /etc/alloy/config.alloy and ships nothing (see #695). Instead we let the
  # image's default entrypoint (`/bin/alloy run /etc/alloy/config.alloy --storage.path=...`,
  # always present) run, and bind-mount OUR config over /etc/alloy/config.alloy below. That
  # makes a recreate self-correcting. Trade-off: no --server.http.listen-addr override, so the
  # Alloy UI binds localhost (it was firewall-blocked externally anyway; OTLP export is outbound).
  initialization {
    hostname = "alloy-${each.value}"
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  cpu {
    architecture = "amd64"
    cores        = 1
    limit        = 0
    units        = 1024
  }

  # Disk for container
  disk {
    mount_options = []
    datastore_id  = "local-lvm"
  }

  # Network - bridge to vmbr0 (adjust if your network setup differs)
  # OCI app containers (entrypoint is /bin/alloy, not /sbin/init) do not run a guest DHCP client.
  # host_managed requires Proxmox VE 9.1+ and bpg/proxmox provider >= 0.104.
  network_interface {
    bridge       = "vmbr0"
    firewall     = true
    host_managed = true
    name         = "eth0"
  }
  console {
    enabled   = true
    tty_count = 2
    type      = "console"
  }

  # Nesting: expose host procfs and sysfs to the guest (per Proxmox docs). With nesting we could use /proc and /sys in Alloy for host metrics; privileged + /host bind is an alternative.
  features {
    nesting = true
  }

  # Unprivileged + nesting: nesting exposes host /proc and /sys to the container, so we use those paths in Alloy (no privileged needed for metrics). /host bind still used for rootfs and host logs.
  unprivileged = true
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
  # Mount the snippets dir (which holds only our config, uploaded as config.alloy) over the image's
  # /etc/alloy, so /etc/alloy/config.alloy IS our config and the image's default entrypoint loads it
  # (#695). This deliberately shadows the image's demo /etc/alloy/config.alloy. mount_point is
  # ForceNew, so changing this recreates the CT -- intended: the recreate is what applies the new layout.
  mount_point {
    path          = "/etc/alloy"
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

# Upload the Alloy config as a snippet named config.alloy. The snippets dir is bind-mounted over the
# container's /etc/alloy (above), so this lands at /etc/alloy/config.alloy -- exactly where the image's
# default entrypoint (`/bin/alloy run /etc/alloy/config.alloy`) reads it (#695). Must be config.alloy.
resource "proxmox_virtual_environment_file" "alloy_config" {
  for_each = local.alloy_nodes
  provider = proxmox.proxmox_root

  node_name    = each.value
  datastore_id = "local"
  content_type = "snippets"
  source_raw {
    data = templatefile("${path.root}/templates/alloy-proxmox.alloy", {
      otlp_tiles = "https://otlp.tiles.symmatree.com"
      hostname   = each.value
    })
    file_name = "config.alloy"
  }
}
