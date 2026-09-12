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

  # Reset on destroy, so a rebuilt cluster does not inherit the old one's state.
  # A VM's disk goes away with the VM; a bare-metal machine survives, keeping
  # STATE (node identity, machine config) and EPHEMERAL (/var, kubelet state,
  # hostname-pinned local-path volumes) from a cluster that no longer exists.
  #
  # This fires only when Terraform destroys the resource -- i.e. when taint-vms
  # was run deliberately. A power cut, a blown circuit or a knock never touches
  # Terraform state, so a wipe is never inferred from boot conditions.
  #
  # reboot: the provider default halts, and these machines have no USB stick to
  # boot from. reset leaves BOOT intact, so the machine comes back up from its
  # own disk into maintenance mode, where this resource's create re-applies
  # config. graceful: false because the control plane is being replaced in the
  # same apply, so the etcd checks a graceful reset enforces cannot pass -- the
  # reset must not depend on the cluster still working.
  #
  # Note: the provider only honours on_destroy once it has been persisted by an
  # apply, so changes here take effect from the *next* destroy, not this one.
  on_destroy = {
    reset    = true
    reboot   = true
    graceful = false
  }

  depends_on = [unifi_user.metal_client]
}
