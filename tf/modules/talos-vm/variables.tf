variable "iso_id" {
  description = "Proxmox ISO file ID for Talos installation"
  type        = string
}

variable "description" {
  description = "Description of the VM"
  type        = string
  default     = null
}

variable "name" {
  description = "Name of the VM"
  type        = string
}

variable "node_name" {
  description = "Proxmox node name where the VM will be created"
  type        = string
}

variable "vm_id" {
  description = "Unique VM ID"
  type        = number
}

variable "num_cores" {
  description = "Number of CPU cores for the VM"
  type        = number
  default     = 2
}

variable "ram_mb" {
  description = "Amount of RAM in MB for the VM"
  type        = number
  default     = 2048
}

variable "disk_size_gb" {
  description = "Disk size in GB for the VM"
  type        = number
  default     = 32
}

variable "mac_address" {
  description = "MAC address for the VM network interface"
  type        = string
}

variable "ip_address" {
  description = "Fixed IP address for the VM in the Unifi controller"
  type        = string
}

variable "domain_name" {
  description = "Domain name for the VM"
  type        = string
  default     = "local.symmatree.com."
}

variable "started" {
  description = "Whether the VM should be started after creation"
  type        = bool
  default     = false
}

variable "apply_config" {
  description = "Whether to apply Talos machine configuration"
  type        = bool
  default     = false
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
