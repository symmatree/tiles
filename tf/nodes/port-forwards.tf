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
