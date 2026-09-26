# Fixed addresses and names for the rekon10 fleet devices (#735).
#
# These are the only machines on this network whose addresses are dynamic leases. Every Talos
# node already gets a `unifi_user` reservation from Terraform; the fleet devices are the same
# kind of thing -- long-lived, addressed by other software, and currently discoverable only by
# asking a human.
#
# The addresses here are NOT the leases they hold today. Those landed in three different /24s
# with no pattern (10.0.99.75, 10.0.5.237, 10.0.2.49), which is an accident of DHCP rather
# than a decision. Reserving them where they sit would preserve the accident; the point of
# declaring them is that the address becomes a reviewable line, so the fleet gets one
# contiguous block in one subnet.
#
# MACs are burned-in wlan0/eth0 addresses read off the running units. They survive a reflash,
# which is what makes them the right key: a card can be rewritten without the reservation
# changing.
#
# NOT here, deliberately: `usb0`. That is the gadget network -- campods static on
# 10.55.0.0/24 with the coordinator bridging, configured in the `coordinator` repo and never
# touching UniFi. Its MACs are locally administered (`02:` prefix), generated rather than
# burned in and pinned on the device by ansible, so they are not an identity to reserve
# against in the first place.

locals {
  # Host numbers within `fleet_subnet`, left as a contiguous block so the fleet reads in
  # order and the two unflashed pods have their places already.
  #
  # campod-ne (.14) and campod-nw (.15) are NOT declared: they have never been flashed and
  # have no MAC. Their numbers are noted here so nothing else claims them.
  fleet_devices = {
    coordinator = {
      host        = 10
      mac         = "2c:cf:67:03:fc:8f"
      description = "rekon10 coordinator (Pi 4B) wlan0"
    }
    coordinator-wired = {
      host        = 11
      mac         = "2c:cf:67:03:fc:8e"
      description = "rekon10 coordinator (Pi 4B) eth0"
    }
    campod-se = {
      host        = 12
      mac         = "88:a2:9e:c3:8f:2c"
      description = "rekon10 campod-se (Zero 2 W) wlan0"
    }
    campod-sw = {
      host        = 13
      mac         = "88:a2:9e:c3:8e:c4"
      description = "rekon10 campod-sw (Zero 2 W) wlan0"
    }
  }
}

resource "unifi_user" "fleet_device" {
  for_each = local.fleet_devices

  mac              = each.value.mac
  name             = each.key
  note             = each.value.description
  fixed_ip         = cidrhost(var.fleet_subnet, each.value.host)
  local_dns_record = "${each.key}.${var.fleet_domain_name}"

  # As with the Talos nodes: these clients already exist in the controller as DHCP leases, so
  # adopt them rather than failing, and do not forget them on destroy.
  allow_existing         = true
  skip_forget_on_destroy = false
  network_id             = data.unifi_network.main.id
}

output "fleet_device_addresses" {
  description = "Reserved address and DNS name per fleet device."
  value = {
    for k, v in local.fleet_devices : k => {
      ip  = cidrhost(var.fleet_subnet, v.host)
      dns = "${k}.${var.fleet_domain_name}"
      mac = v.mac
    }
  }
}
