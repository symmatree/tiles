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
* Create Github fine-grained PAT (see [GitHub Token Rotation Guide](../docs/github-token-rotation.md))
* Be logged into GCP both directly and as application-default

## Running Terraform

Terraform requires two secrets to be provided as environment variables:

```bash
cd tf/bootstrap
export TF_VAR_onepassword_sa_token=$(op read op://tiles-secrets/tiles-onepassword-sa/credential)
export TF_VAR_github_token=$(op read op://tiles-secrets/github-tiles-tf-bootstrap/password)
terraform plan
terraform apply
```

**Note**: The GitHub token is used for provider authentication AND is stored back into 1Password with metadata via the `github-app-token` module. This enables:
- Tracking token expiration and rotation dates
- Documenting token permissions and usage
- Automatic propagation to Kubernetes via 1Password Operator

## GitHub Token Management

This bootstrap module manages GitHub tokens using the reusable `github-app-token` module. Tokens are:
1. Provided via `TF_VAR_github_token` environment variable
2. Used to authenticate the GitHub terraform provider
3. Stored in 1Password with metadata (expiration, permissions, last rotation)
4. Automatically synced to Kubernetes secrets via 1Password Operator

For detailed information on creating, rotating, and troubleshooting GitHub tokens, see:
**[GitHub Token Rotation Guide](../docs/github-token-rotation.md)**
