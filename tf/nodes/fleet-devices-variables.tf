variable "fleet_subnet" {
  description = <<-EOT
    Subnet the rekon10 fleet devices are reserved in, e.g. "10.0.20.0/24".

    Deliberately has no default. The devices' current addresses are DHCP leases spread across
    three unrelated /24s, and choosing the block is a network decision rather than something
    to inherit from whatever the controller happened to hand out. See symmatree/tiles#735.
  EOT
  type        = string
}

variable "fleet_domain_name" {
  description = "Domain the fleet devices' local DNS records are created under."
  type        = string
  default     = "local.symmatree.com"
}
