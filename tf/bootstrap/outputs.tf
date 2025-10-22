variable "unifi_network_id" {
  description = "The ID of the UniFi network to retrieve."
  type        = string
}

data "unifi_network" "main" {
  id = var.unifi_network_id
}

output "unifi_network" {
  description = "The UniFi network details."
  value       = data.unifi_network.main
}
