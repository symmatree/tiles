resource "unifi_user" "metal_client" {
  mac                    = var.mac_address
  name                   = var.name
  note                   = var.description != null ? "${var.description} - ${var.name}" : var.name
  fixed_ip               = var.ip_address
  local_dns_record       = "${var.name}.${var.domain_name}"
  allow_existing         = true
  skip_forget_on_destroy = false
  network_id             = var.unifi_network_id
}

resource "talos_machine_configuration_apply" "this" {
  client_configuration        = var.client_configuration
  machine_configuration_input = var.machine_configuration
  node                        = var.ip_address
  config_patches              = var.config_patches

  # Defaults to "reboot" (var.apply_mode): this resource only re-runs when the
  # metal config actually changes, and rebooting then guarantees the change
  # fully takes effect and lets a rebuilt node rejoin the new etcd. "auto" would
  # reboot only when Talos judges a field requires it (unreliable -- Talos can
  # hold state until reboot), and on a rebuild's byte-identical re-apply "auto"
  # is a no-op that leaves the node orphaned.
  # docs/bare-metal-nodes.md#rebuilds-metal-reapply--reboot
  apply_mode = var.apply_mode

  depends_on = [unifi_user.metal_client]
}
