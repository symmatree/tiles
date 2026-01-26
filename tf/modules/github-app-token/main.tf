terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = ">= 2.1.2"
    }
  }
}

variable "vault_uuid" {
  description = "1Password vault UUID where the token will be stored"
  type        = string
}

variable "token_name" {
  description = "Name for the token item in 1Password"
  type        = string
}

variable "token_value" {
  description = "The GitHub token value (PAT or App token)"
  type        = string
  sensitive   = true
}

variable "token_username" {
  description = "GitHub username or organization name for this token (optional, defaults to token owner)"
  type        = string
  default     = ""
}

variable "token_description" {
  description = "Description of what this token is used for"
  type        = string
  default     = ""
}

# Generate Grafana datasource.yaml configuration from the token
locals {
  datasource_yaml = templatefile("${path.module}/datasource.yaml.tpl", {
    token = var.token_value
  })
}

# Store the GitHub token in 1Password
resource "onepassword_item" "github_token" {
  vault    = var.vault_uuid
  title    = var.token_name
  category = "password"

  password = var.token_value
  username = var.token_username != "" ? var.token_username : null

  # Store datasource.yaml for Grafana sidecar
  section {
    label = "grafana"
    field {
      label = "datasource.yaml"
      value = local.datasource_yaml
      type  = "CONCEALED"
    }
  }

  section {
    label = "metadata"
    field {
      label = "description"
      value = var.token_description
    }
    field {
      label = "source"
      value = "managed by terraform"
    }
    field {
      label = "root_module"
      value = basename(abspath(path.root))
    }
    field {
      label = "module"
      value = basename(abspath(path.module))
    }
  }
}

output "onepassword_item_uuid" {
  description = "UUID of the 1Password item containing the token"
  value       = onepassword_item.github_token.uuid
}

output "onepassword_item_title" {
  description = "Title of the 1Password item"
  value       = onepassword_item.github_token.title
}

output "onepassword_reference" {
  description = "1Password CLI reference for the token"
  value       = "op://${var.vault_uuid}/${var.token_name}/password"
}
