# GitHub App Token Module

This module manages GitHub tokens (PAT or GitHub App tokens) and stores them securely in 1Password.

## Purpose

This module provides a standardized way to:
1. Store GitHub tokens in 1Password with metadata
2. Track token expiration and last rotation date
3. Document token permissions and scope
4. Enable automated token rotation workflows

## Usage

### Basic Usage with Manual PAT

```hcl
module "github_token" {
  source = "../modules/github-app-token"

  vault_uuid        = data.onepassword_vault.tf_secrets.uuid
  token_name        = "github-tiles-tf-bootstrap"
  token_value       = var.github_token
  token_description = "GitHub PAT for Terraform provider in tf/bootstrap"
  
  expiration_days = 90
  
  token_permissions = {
    contents       = "write"
    administration = "write"
    metadata       = "read"
  }
}
```

### Token Rotation Workflow

#### Initial Setup

1. Create a GitHub Fine-Grained Personal Access Token:
   - Go to GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens
   - Click "Generate new token"
   - Set expiration to 90 days (or desired duration)
   - Select repositories and permissions as needed
   - Copy the token (you won't see it again!)

2. Run Terraform to store the token:
   ```bash
   cd tf/bootstrap
   export TF_VAR_onepassword_sa_token=$(op read op://tiles-secrets/tiles-onepassword-sa/credential)
   export TF_VAR_github_token="YOUR_NEW_TOKEN_HERE"
   terraform apply
   ```

#### Periodic Rotation (Every 90 days)

1. Generate a new GitHub token (same process as above)
2. Update and re-apply Terraform:
   ```bash
   export TF_VAR_github_token="YOUR_NEW_TOKEN_HERE"
   terraform apply
   ```
3. Verify services restart automatically via 1Password operator (if configured with auto-restart)

#### Recovery Path

If manual rotation is missed for an extended period:

1. Generate a new token immediately
2. Run terraform apply to update 1Password
3. For services without auto-restart:
   - Check which services use the token (see Usage tracking below)
   - Manually restart affected pods: `kubectl rollout restart deployment/<name> -n <namespace>`

### Usage Tracking

Track where tokens are used by checking:
- `charts/*/templates/*secret*.yaml` for OnePasswordItem references
- Workflow files in `.github/workflows/` for token usage
- Build scripts like `charts/mimir/webhook/build.sh`

### Future Enhancement: GitHub App Support

When a GitHub App is created for automated token rotation:

1. Create a GitHub App at https://github.com/settings/apps/new with:
   - Required permissions for your use case
   - Install the app on your organization/repositories

2. Store the App credentials in 1Password:
   - App ID
   - Installation ID  
   - Private key (PEM file)

3. Update the terraform provider to use app_auth:
   ```hcl
   provider "github" {
     owner = var.github_owner
     app_auth {
       id              = var.github_app_id
       installation_id = var.github_app_installation_id
       pem_file        = var.github_app_pem_file
     }
   }
   ```

4. The provider will then automatically generate short-lived installation tokens

## Variables

- `vault_uuid` - UUID of the 1Password vault for storage
- `token_name` - Name for the 1Password item (e.g., "github-tiles-tf-bootstrap")
- `token_value` - The actual token value (sensitive)
- `token_description` - Human-readable description of token purpose
- `token_repositories` - List of repositories with access (optional, empty = all repos)
- `token_permissions` - Map of permission names to access levels
- `expiration_days` - Days until token expires (1-365, default 90)

## Outputs

- `onepassword_item_uuid` - UUID of the created 1Password item
- `onepassword_item_title` - Title of the item
- `onepassword_reference` - CLI reference string for retrieving the token

## Design Notes

### Why Not Automatic Rotation Yet?

GitHub's API doesn't support programmatic creation of user PATs. The options are:
1. **Manual PAT rotation** (current approach) - Simple, secure, requires periodic manual work
2. **GitHub App tokens** (future approach) - Automated, short-lived, requires GitHub App setup

We're starting with #1 for simplicity and will migrate to #2 when we set up a GitHub App.

### Why Store in 1Password?

1. **Central secret management** - Single source of truth for all secrets
2. **Integration** - 1Password Operator can sync to Kubernetes automatically
3. **Access control** - Fine-grained permissions via 1Password
4. **Audit trail** - Track who accessed secrets and when
5. **Backup/recovery** - 1Password handles backup and DR

### Metadata Tracking

The module stores metadata with each token:
- `description` - What the token is used for
- `source` - "managed by terraform" 
- `expiration_days` - How long before rotation needed
- `last_rotated` - Timestamp of last update
- `permissions` - Required scopes/permissions

This makes it easy to:
- Audit token usage
- Plan rotation schedule
- Troubleshoot permission issues
- Track token lifecycle
