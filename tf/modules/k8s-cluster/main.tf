
variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
}

variable "gcp_region" {
  description = "Google Cloud region"
  type        = string
}

variable "cluster_name" {
  description = "Cluster name"
  type        = string
}

variable "onepassword_vault" {
  description = "1Password vault UUID."
  type        = string
}
