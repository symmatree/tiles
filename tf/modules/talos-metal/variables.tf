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

variable "unifi_network_id" {
  description = "Unifi network ID for the metal node"
  type        = string
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

# Apply mode for talos_machine_configuration_apply. Default "auto" reboots only
# when a changed field requires it -- and is a no-op (no reboot) when the config
# is byte-identical, which is what leaves metal workers orphaned after a cluster
# re-bootstrap. Set to "reboot" (via metal_apply_mode) during a rebuild so a
# re-applied metal node reboots and rejoins the new etcd. See
# docs/bare-metal-nodes.md#rebuilds-metal-reapply--reboot.
variable "apply_mode" {
  description = "talosctl apply-config mode for the metal node: auto | no_reboot | reboot | staged. Defaults to \"reboot\" so a config change fully applies (and a rebuild rejoins the new etcd); the resource only re-runs on an actual config change, so this is not a reboot-every-apply."
  type        = string
  default     = "reboot"

  validation {
    condition     = contains(["auto", "no_reboot", "reboot", "staged"], var.apply_mode)
    error_message = "apply_mode must be one of: auto, no_reboot, reboot, staged."
  }
}
