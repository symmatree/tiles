# tf/nodes

Terraform configuration for managing cluster nodes, including VMs, bare metal nodes, and associated infrastructure.

## Prerequisites

* 1Password vault with required secrets (see `docs/secrets.md`)
* GCP authentication configured (both direct and application-default)
* Access to Proxmox, UniFi, Synology, and Cloudflare APIs

## Required Environment Variables

The following environment variables must be set before running Terraform:

### 1Password Service Account Token

Required for accessing secrets from 1Password:

```bash
export TF_VAR_onepassword_sa_token=$(op read op://tiles-secrets/tiles-onepassword-sa/credential)
```

### UniFi Controller Credentials

Required for managing UniFi network resources:

```bash
export UNIFI_USERNAME=$(op read op://tiles-secrets/morpheus-terraform/username)
export UNIFI_PASSWORD=$(op read op://tiles-secrets/morpheus-terraform/password)
```

### Synology NAS Credentials

Required for managing Synology resources:

```bash
export SYNOLOGY_USER=$(op read op://tiles-secrets/raconteur-login/username)
export SYNOLOGY_PASSWORD=$(op read op://tiles-secrets/raconteur-login/password)
# Optional: override the host from terraform.tfvars
# export SYNOLOGY_HOST="https://raconteur.ad.local.symmatree.com:5001"
```

### Proxmox Root Credentials

Required for bind mounts in Proxmox containers (e.g., Alloy monitoring containers):

```bash
export TF_VAR_proxmox_root_password=$(op read op://tiles-secrets/proxmox-root/password)
```

## Usage

**IMPORTANT**: You MUST select a workspace (`test` or `prod`) before running Terraform. Running in the default workspace is dangerous and not supported.

```bash
cd tf/nodes
eval $(op signin)

# Set required environment variables
export TF_VAR_onepassword_sa_token=$(op read op://tiles-secrets/tiles-onepassword-sa/credential)
export UNIFI_USERNAME=$(op read op://tiles-secrets/morpheus-terraform/username)
export UNIFI_PASSWORD=$(op read op://tiles-secrets/morpheus-terraform/password)
export SYNOLOGY_USER=$(op read op://tiles-secrets/raconteur-login/username)
export SYNOLOGY_PASSWORD=$(op read op://tiles-secrets/raconteur-login/password)
export TF_VAR_proxmox_root_password=$(op read op://tiles-secrets/proxmox-root/password)

# Select workspace (test or prod)
terraform workspace select test  # or 'prod' for production

# Run plan with the appropriate tfvars file
terraform plan -var-file=test.tfvars  # or 'prod.tfvars' for production
```

## Workspaces

This configuration supports two workspaces:
- **test**: For the test cluster (`tiles-test`)
- **prod**: For the production cluster (`tiles`)

Each workspace has its own `.tfvars` file (`test.tfvars` or `prod.tfvars`) that must be specified with `-var-file` when running `terraform plan` or `terraform apply`. The workspace must be selected before running any Terraform commands.
