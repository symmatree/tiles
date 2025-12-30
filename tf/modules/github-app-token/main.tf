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

variable "token_repositories" {
  description = "List of repositories the token should have access to (empty for all repos)"
  type        = list(string)
  default     = []
}

variable "token_permissions" {
  description = "Permissions for the token. Map of permission names to access levels (read, write, admin)"
  type        = map(string)
  default = {
    contents      = "read"
    metadata      = "read"
    packages      = "read"
    pull_requests = "read"
  }
}

variable "expiration_days" {
  description = "Number of days until token expires (1-365)"
  type        = number
  default     = 90
  validation {
    condition     = var.expiration_days >= 1 && var.expiration_days <= 365
    error_message = "Token expiration must be between 1 and 365 days"
  }
}

# Store the GitHub token in 1Password
resource "onepassword_item" "github_token" {
  vault    = var.vault_uuid
  title    = var.token_name
  category = "password"

  password = var.token_value
  username = var.token_username != "" ? var.token_username : null

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
    field {
      label = "expiration_days"
      value = tostring(var.expiration_days)
    }
    field {
      label = "last_rotated"
      value = plantimestamp()
    }
  }

  section {
    label = "permissions"
    dynamic "field" {
      for_each = var.token_permissions
      content {
        label = field.key
        value = field.value
      }
    }
  }

  dynamic "section" {
    for_each = length(var.token_repositories) > 0 ? [1] : []
    content {
      label = "repositories"
      field {
        label = "repos"
        value = join(", ", var.token_repositories)
      }
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
