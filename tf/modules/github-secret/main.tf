terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

variable "repository" {
  description = "The name of the GitHub repository"
  type        = string
}

variable "secret_name" {
  description = "The name of the secret"
  type        = string
}

variable "plaintext_value" {
  description = "The plaintext value of the secret"
  type        = string
  sensitive   = true
}

resource "github_actions_secret" "main" {
  repository      = var.repository
  secret_name     = var.secret_name
  plaintext_value = var.plaintext_value
}

resource "github_dependabot_secret" "dependabot" {
  repository      = var.repository
  secret_name     = var.secret_name
  plaintext_value = var.plaintext_value
}
