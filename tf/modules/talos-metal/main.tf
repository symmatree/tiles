resource "unifi_client" "metal_client" {
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

  depends_on = [unifi_client.metal_client]
}
