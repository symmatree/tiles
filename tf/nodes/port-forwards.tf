# UniFi WAN port-forwards for the cluster's public front door.
#
# Only created when ingress_lb_ip is set (prod). 443 -> the shared Cilium
# ingress VIP; oauth2-proxy (or per-service auth) gates what is behind it.
resource "unifi_port_forward" "shared_ingress_https" {
  count = var.ingress_lb_ip != "" ? 1 : 0

  name                   = "shared-ingress-https"
  port_forward_interface = "wan"
  protocol               = "tcp"
  dst_port               = "443"
  fwd_ip                 = var.ingress_lb_ip
  fwd_port               = "443"
}

# The mutual-TLS door. Separate port because 443 forwards to the shared
# ingress and the two cannot be multiplexed on it: ghostunnel is a single-target
# TCP proxy, and TLS passthrough routing is unavailable here (no tlsroutes CRD,
# and the Cilium ingress terminates TLS so it cannot hand on a raw handshake).
#
# Nothing behind this port is gated by oauth2-proxy. ghostunnel requires a client
# certificate from the device-identity CA and refuses to start without an access
# control flag at all, so the gate is the handshake rather than anything HTTP.
resource "unifi_port_forward" "homeassistant_tls" {
  count = var.homeassistant_tls_lb_ip != "" ? 1 : 0

  name                   = "homeassistant-tls"
  port_forward_interface = "wan"
  protocol               = "tcp"
  dst_port               = var.homeassistant_tls_port
  fwd_ip                 = var.homeassistant_tls_lb_ip
  fwd_port               = var.homeassistant_tls_port
}
