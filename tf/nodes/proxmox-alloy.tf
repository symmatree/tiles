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
# Operational note: config is delivered as the snippet config.alloy bind-mounted over the CT's
# /etc/alloy, and loaded by an entrypoint set to the image default (`/bin/alloy run
# /etc/alloy/config.alloy ...`); see the initialization block. A config-content change updates the
# snippet but a running CT keeps the old file open until restarted. This layout is robust to bpg#2789:
# the entrypoint and mount both converge on our config regardless of whether the provider applies our
# override or the image default -- and it always boots (an OCI CT with no entrypoint execs the
# nonexistent /sbin/init and dies; that was the #696 outage, not the mount).
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
  depends_on = [proxmox_virtual_environment_file.alloy_config, proxmox_virtual_environment_file.alloy_journal_hook]

  node_name = each.value
  vm_id     = local.alloy_vm_ids[each.key]

  # Hookscript runs on the host at pre-start and setfacls the systemd journal so this unprivileged
  # CT can read it for host-log collection (#686; see alloy-journal-hook.sh + the loki.source.journal
  # block in the template). Must be executable, which is why the file below uploads via SFTP w/ 0755.
  hook_script_file_id = proxmox_virtual_environment_file.alloy_journal_hook[each.value].id

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
  # Entrypoint is set explicitly to the SAME command the OCI image already uses --
  # `/bin/alloy run /etc/alloy/config.alloy ...` -- and we bind-mount our config over /etc/alloy below.
  # This is robust to bpg#2789 (the provider not reliably applying our entrypoint to OCI containers on
  # create): whether the provider applies THIS value or falls back to the image-derived one, both are
  # `/bin/alloy run /etc/alloy/config.alloy`, and /etc/alloy/config.alloy is our config via the mount --
  # so the CT boots and loads our config either way.
  #
  # Why an explicit entrypoint (rather than none): #696 removed the entrypoint entirely, expecting
  # Proxmox to fall back to the image's entrypoint. It does NOT -- it execs `/sbin/init`, which does not
  # exist in the app-container image (`Failed to exec "/sbin/init"` -> spawn fails -> the whole feed went
  # down). The `/etc/alloy` mount itself is fine (an OCI CT boots with it as long as an entrypoint is
  # set); the missing entrypoint was the actual #696 failure.
  initialization {
    hostname   = "alloy-${each.value}"
    entrypoint = "/bin/alloy run /etc/alloy/config.alloy '--storage.path=/var/lib/alloy/data' '--server.http.listen-addr=0.0.0.0:12345'"
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

  # Mount host root filesystem (read-only) at /host for node_exporter rootfs/filesystem metrics.
  # NOTE: this bind is NON-recursive, so it does NOT carry the /proc and /sys submounts (/host/proc is
  # empty without the explicit binds below). Same approach as Synology - bind mount host root to /host.
  mount_point {
    path          = "/host"
    read_only     = true
    mount_options = []
    volume        = "/"
  }
  # Bind-mount the snippets dir (holds our config.alloy) over the container's /etc/alloy, so
  # /etc/alloy/config.alloy IS our config -- exactly where the entrypoint above reads it. This shadows
  # the image's demo /etc/alloy/config.alloy (the snippets dir holds only our file). Mounting here is
  # fine as long as an entrypoint is set (verified: boots + ships); #696's outage was the *removed*
  # entrypoint (-> /sbin/init), not this mount.
  mount_point {
    path          = "/etc/alloy"
    read_only     = true
    mount_options = []
    volume        = "/var/lib/vz/snippets"
  }
  # Bind the host's live procfs and sysfs so node_exporter reads HOST memory/CPU, not the
  # lxcfs-virtualized 512 MB cgroup view (#544). procfs_path=/host/proc, sysfs_path=/host/sys in the
  # template. No privilege needed (/proc/meminfo, /sys are world-readable). Ordered LAST so they append
  # as mp2/mp3 (mount_point is ForceNew -- matching the live CTs' mp numbering keeps the apply a no-op).
  mount_point {
    path          = "/host/proc"
    read_only     = true
    mount_options = []
    volume        = "/proc"
  }
  mount_point {
    path          = "/host/sys"
    read_only     = true
    mount_options = []
    volume        = "/sys"
  }
  # Start on boot
  start_on_boot = true

  # Tags for identification
  tags = ["alloy", "monitoring"]

  # Notes
  description = "Alloy monitoring container for ${each.value} - collects host metrics and logs via node_exporter (hwmon sensors) and system logs"
}

# Upload the Alloy config as a snippet named config.alloy. The snippets dir is bind-mounted over the
# CT's /etc/alloy, so this lands at /etc/alloy/config.alloy -- where the entrypoint reads it. Must be
# named config.alloy (it shadows the image's demo /etc/alloy/config.alloy).
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

# Upload the CT hookscript as an EXECUTABLE snippet. Proxmox refuses a non-executable hookscript, and
# the API upload path can't set the exec bit -- so this uses upload_mode = "sftp" + file_mode = "0755"
# (requires the provider `ssh` block in main.tf). Referenced by hook_script_file_id on the CT above;
# it grants the CT read on the host journal at pre-start so loki.source.journal works unprivileged (#686).
resource "proxmox_virtual_environment_file" "alloy_journal_hook" {
  for_each = local.alloy_nodes
  provider = proxmox.proxmox_root

  node_name    = each.value
  datastore_id = "local"
  content_type = "snippets"
  file_mode    = "0755"
  upload_mode  = "sftp"
  source_raw {
    data      = file("${path.root}/templates/alloy-journal-hook.sh")
    file_name = "alloy-journal-hook"
  }
}
