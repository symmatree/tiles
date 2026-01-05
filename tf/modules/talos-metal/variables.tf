variable "description" {
  description = "Description of the VM"
  type        = string
  default     = null
}

variable "name" {
  description = "Name of the VM"
  type        = string
}

variable "mac_address" {
  description = "MAC address for the metal node"
  type        = string
}

variable "ip_address" {
  description = "Fixed IP address for the metal node in the Unifi controller"
  type        = string
}

variable "domain_name" {
  description = "Domain name for the metal node"
  type        = string
  default     = "local.symmatree.com."
}

variable "client_configuration" {
  description = "Talos client configuration for applying machine config"
  type = object({
    ca_certificate     = string
    client_certificate = string
    client_key         = string
  })
  default   = null
  sensitive = true
}

variable "machine_configuration" {
  description = "Talos machine configuration to apply"
  type        = string
  default     = null
  sensitive   = true
}

variable "config_patches" {
  description = "List of config patches to apply (YAML strings or file paths)"
  type        = list(string)
  default     = []
}
