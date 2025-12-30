# tf/bootstrap

Initial block of terraform that is run as "yourself" interactively, except
for a few cases where that became too much of a pain.

## Pre-work

* Create a 1password vault for the repo

### 1Password Service Account

There are two related things that 1password kinds of conflates.

Go to [1password's service account site](https://my.1password.com/developer-tools/active/service-accounts)


* Create a 1password service account token, will be used as
  `var.onepassword_sa_token`. (Note: The 1password terraform provider
  doesn't expose the service-account or Connect-token APIs, and
  it was more trouble than it was worth when I tried to use
  environment variables to use personal creds.)
* Create SA and VPN cilent config (allowing Github to connect to Wireguard) in Unifi
* Create ProxMox root login (this module will create a service account for downstream use)
* **Authentication Options:**
  * **Option A - GitHub App (Recommended)**: Create a GitHub App for automated token generation. See [GitHub App Setup Guide](../docs/github-app-setup.md) for detailed instructions.
  * **Option B - Personal Access Token**: Create a GitHub fine-grained PAT. See [GitHub Token Rotation Guide](../docs/github-token-rotation.md).
* Be logged into GCP both directly and as application-default

## Running Terraform

Terraform requires two secrets to be provided as environment variables.

### Option A: GitHub App Authentication (Recommended)

For automated, programmatic token generation with short-lived (1 hour) tokens:

```bash
cd tf/bootstrap
export TF_VAR_onepassword_sa_token=$(op read op://tiles-secrets/tiles-onepassword-sa/credential)

# GitHub App credentials
export TF_VAR_github_app_id=$(op read op://tiles-secrets/github-app-tiles-tf/app_details/app_id)
export TF_VAR_github_app_installation_id=$(op read op://tiles-secrets/github-app-tiles-tf/app_details/installation_id)
export TF_VAR_github_app_pem_file=$(op read op://tiles-secrets/github-app-tiles-tf/password)
export TF_VAR_github_owner="symmatree"

terraform plan
terraform apply
```

See [GitHub App Setup Guide](../docs/github-app-setup.md) for initial setup.

### Option B: Personal Access Token Authentication

For manual token management with 90-day rotation:

```bash
cd tf/bootstrap
export TF_VAR_onepassword_sa_token=$(op read op://tiles-secrets/tiles-onepassword-sa/credential)
export TF_VAR_github_token=$(op read op://tiles-secrets/github-tiles-tf-bootstrap/password)
export TF_VAR_github_owner="symmatree"

terraform plan
terraform apply
```

**Note**: When using PAT authentication, the token is stored back into 1Password with metadata via the `github-app-token` module.

## GitHub Token Management

This bootstrap module supports two authentication modes:

### GitHub App (Recommended)

**Advantages:**
- Automatic token generation via API (no manual creation)
- Short-lived tokens (1 hour expiration, auto-refreshed by Terraform)
- No manual rotation needed
- Better security and audit trail

**Setup:** See [GitHub App Setup Guide](../docs/github-app-setup.md)

### Personal Access Token

**Advantages:**
- Simpler initial setup
- No GitHub App required
- Works immediately

**Disadvantages:**
- Manual token creation and rotation (every 90 days)
- Longer-lived tokens

**Setup:** See [GitHub Token Rotation Guide](../docs/github-token-rotation.md)

## Generating Tokens for Services

For services like Grafana that need standalone GitHub tokens (not directly managed by Terraform):

**With GitHub App:**
```bash
# Generate a short-lived token (expires in 1 hour)
./scripts/generate-github-app-token.sh --token-name grafana-github-token
```

**With PAT:**
Create and rotate tokens manually as documented in the rotation guide.
