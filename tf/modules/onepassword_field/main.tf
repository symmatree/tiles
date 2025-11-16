required_providers {
  onepassword = {
    source  = "1Password/onepassword"
    version = ">= 2.1.2"
  }
}

variable "vault_name" {
  type        = string
  description = "The name of the 1Password vault to use for storing secrets."
}

variable "item_name" {
  type        = string
  description = "The name of the 1Password item to retrieve."
}

variable "section_name" {
  type        = string
  description = "The name of the 1Password section to retrieve."
}

variable "field_name" {
  type        = string
  description = "The name of the 1Password field to retrieve."
}

data "onepassword_vault" "vault" {
  name = var.vault_name
}

data "onepassword_item" "item" {
  vault = data.onepassword_vault.vault.uuid
  title = var.item_name
}

locals {
  section = [for section in data.onepassword_item.item.section :
    section if section.label == var.section_name
  ][0]

  field = [for field in local.section.field :
    field if field.label == var.field_name
  ][0]
}

output "vault_uuid" {
  value = data.onepassword_vault.vault.uuid
}

output "item_value" {
  value     = data.onepassword_item.item
  sensitive = true
}

output "section_value" {
  value     = local.section
  sensitive = true
}

output "field_value" {
  value     = local.field.value
  sensitive = true
}

terraform {
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = ">= 2.1"
    }
  }
}
