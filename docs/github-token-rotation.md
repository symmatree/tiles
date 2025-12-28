# GitHub Token Rotation Guide

This document describes the GitHub token management and rotation workflow for the Tiles infrastructure.

## Overview

We use GitHub Personal Access Tokens (PATs) for various integrations:
- **Terraform GitHub provider** (`github-tiles-tf-bootstrap`) - Manages GitHub repository configuration
- **Grafana GitHub data source** (`grafana-github-token`) - Provides GitHub metrics to Grafana
- **Build workflows** - Used by mimir webhook and other build processes

All tokens are managed through Terraform and stored in 1Password, with automatic propagation to Kubernetes via the 1Password Operator.

## Architecture

```
┌─────────────────────────────────────┐
│ Manual Token Creation (GitHub UI)  │
│  - Fine-grained PAT with 90d expiry │
└──────────────┬──────────────────────┘
               │
               ↓ (apply via terraform)
┌─────────────────────────────────────┐
│ Terraform (tf/bootstrap)            │
│  - Validates token                  │
│  - Stores in 1Password with metadata│
└──────────────┬──────────────────────┘
               │
               ↓ (automatic sync)
┌─────────────────────────────────────┐
│ 1Password Operator (Kubernetes)     │
│  - Syncs tokens to K8s secrets      │
│  - Triggers pod restarts (auto)     │
└──────────────┬──────────────────────┘
               │
               ↓ (consumed by)
┌─────────────────────────────────────┐
│ Services & Workflows                │
│  - Grafana (via secret)             │
│  - GitHub Actions (via 1Password)   │
│  - Build scripts (via op CLI)       │
└─────────────────────────────────────┘
```

## Token Types and Scopes

### 1. Terraform Bootstrap Token (`github-tiles-tf-bootstrap`)

**Purpose**: Used by Terraform to manage GitHub repository configuration (branch protection, secrets, etc.)

**Required Permissions**:
- `administration`: write (manage repo settings)
- `contents`: write (manage repository content)
- `metadata`: read (read repository metadata)
- `secrets`: write (manage repository secrets)
- `workflows`: write (manage GitHub Actions workflows)

**Repositories**: `symmatree/tiles`

**Expiration**: 90 days

**Used By**:
- Terraform apply in `tf/bootstrap`
- Manual infrastructure changes

### 2. Grafana GitHub Token (`grafana-github-token`)

**Purpose**: Read-only access for Grafana to pull GitHub metrics and data

**Required Permissions**:
- `contents`: read
- `metadata`: read
- `pull_requests`: read
- `issues`: read

**Repositories**: `symmatree/tiles`

**Expiration**: 90 days

**Used By**:
- Grafana GitHub data source
- Mimir webhook build script
- Other monitoring integrations

## Initial Setup

### Prerequisites

1. 1Password CLI installed and authenticated:
   ```bash
   op signin
   ```

2. Access to the tiles-secrets vault in 1Password

3. Access to GitHub with permission to create PATs

### Creating Tokens

1. **Generate Fine-Grained PAT on GitHub**:
   - Go to https://github.com/settings/tokens?type=beta
   - Click "Generate new token"
   - Configure:
     - **Name**: Descriptive name (e.g., "Tiles Terraform Bootstrap - 2025-Q1")
     - **Expiration**: 90 days
     - **Repository access**: Select `symmatree/tiles`
     - **Permissions**: Set according to token type above
   - Click "Generate token"
   - **Important**: Copy the token immediately (you won't see it again!)

2. **Apply Token via Terraform**:
   ```bash
   cd tf/bootstrap
   
   # Export required variables
   export TF_VAR_onepassword_sa_token=$(op read op://tiles-secrets/tiles-onepassword-sa/credential)
   export TF_VAR_github_token="github_pat_YOUR_TOKEN_HERE"
   
   # Validate the plan
   terraform plan
   
   # Apply changes
   terraform apply
   ```

3. **Verify Storage in 1Password**:
   ```bash
   # Check that tokens are stored
   op item get "github-tiles-tf-bootstrap" --vault tiles-secrets
   op item get "grafana-github-token" --vault tiles-secrets
   ```

4. **Verify Kubernetes Sync** (if cluster is running):
   ```bash
   # Check that 1Password operator synced the secret
   kubectl get secret github-data-source-secret -n grafana
   
   # Verify Grafana pod restarted (if auto-restart is enabled)
   kubectl get pods -n grafana
   ```

## Periodic Rotation (Every 90 Days)

### Rotation Schedule

Set a calendar reminder for **7 days before** token expiration. This gives you time to rotate before services break.

### Rotation Process

1. **Generate New Token**:
   - Follow the same process as "Creating Tokens" above
   - Use a clear name indicating the quarter/year (e.g., "Tiles Terraform Bootstrap - 2025-Q2")

2. **Apply New Token**:
   ```bash
   cd tf/bootstrap
   export TF_VAR_github_token="github_pat_NEW_TOKEN_HERE"
   terraform apply
   ```

3. **Verify Automatic Propagation**:
   
   The 1Password Operator will automatically:
   - Sync the new token to Kubernetes secrets
   - Trigger rolling restarts of pods with `operator.1password.io/auto-restart: "true"`
   
   ```bash
   # Watch for pod restarts
   kubectl get pods -n grafana -w
   ```

4. **Revoke Old Token** (optional but recommended):
   - Go to https://github.com/settings/tokens?type=beta
   - Find the old token
   - Click "Revoke"

5. **Update Terraform Metadata**:
   
   The module automatically updates `last_rotated` timestamp in 1Password metadata.
   You can verify with:
   ```bash
   op item get "github-tiles-tf-bootstrap" --vault tiles-secrets --fields label=last_rotated
   ```

## Recovery Path

If token rotation is missed and tokens expire:

### Immediate Action

1. **Generate emergency token**:
   - Create new fine-grained PAT immediately (follow "Creating Tokens")
   - Apply via Terraform as usual

2. **Identify affected services**:
   ```bash
   # Check for pods referencing GitHub tokens
   kubectl get onepassworditem --all-namespaces | grep github
   ```

3. **Manual restart if needed** (if auto-restart fails):
   ```bash
   # Restart Grafana
   kubectl rollout restart deployment grafana -n grafana
   
   # Check other affected services
   # (most services should auto-restart via 1Password operator)
   ```

### Extended Absence Recovery

If you've been away for a long period and multiple services may be affected:

1. **Create fresh token** with full permissions
2. **Run Terraform apply** to update 1Password
3. **Systematic service check**:
   ```bash
   # List all OnePasswordItem resources
   kubectl get onepassworditem --all-namespaces -o yaml | grep -A5 "github"
   
   # Restart each namespace that uses GitHub tokens
   kubectl rollout restart deployment -n grafana
   kubectl rollout restart deployment -n <other-namespaces>
   ```
4. **Verify each service**:
   - Grafana: Check GitHub data source is working
   - Workflows: Trigger a test workflow run
   - Build scripts: Run a test build

## Token Usage Tracking

### Where Tokens Are Used

1. **Kubernetes (via 1Password Operator)**:
   ```bash
   # Find all OnePasswordItem references
   grep -r "grafana-github-token\|github-tiles-tf-bootstrap" charts/*/templates/
   ```
   
   Currently:
   - `charts/grafana/templates/github-data-source-secret.yaml`

2. **GitHub Actions Workflows**:
   ```bash
   # Find workflow token usage
   grep -r "GITHUB_TOKEN\|github.*token" .github/workflows/
   ```
   
   Note: Most workflows use the automatic `${{ github.token }}` which is managed by GitHub Actions.

3. **Build Scripts**:
   ```bash
   # Find script token usage  
   grep -r "op read.*github" charts/*/webhook/
   ```
   
   Currently:
   - `charts/mimir/webhook/build.sh`

### Adding Auto-Restart to New Services

When adding a new service that uses GitHub tokens:

1. **Create OnePasswordItem with annotation**:
   ```yaml
   apiVersion: onepassword.com/v1
   kind: OnePasswordItem
   metadata:
     name: my-service-github-secret
     annotations:
       operator.1password.io/auto-restart: "true"  # Enable auto-restart
   spec:
     itemPath: "vaults/tiles-secrets/items/grafana-github-token"
   ```

2. **Document in this guide** under "Where Tokens Are Used"

3. **Test the auto-restart**:
   ```bash
   # Manually update the secret value in 1Password
   # Then watch for pod restart
   kubectl get pods -n <namespace> -w
   ```

## Monitoring and Alerts

### Token Expiration Monitoring

Check token expiration dates:

```bash
# View token metadata including expiration
op item get "github-tiles-tf-bootstrap" --vault tiles-secrets --format json | \
  jq -r '.fields[] | select(.label == "expiration_days" or .label == "last_rotated")'
```

### Recommended Monitoring

Set up the following alerts:

1. **Calendar Reminder**:
   - Create recurring event every 90 days
   - Set reminder 7 days before
   - Include link to this document

2. **GitHub Token Expiration** (future):
   - Query GitHub API for token expiration
   - Alert at 7 days before expiration
   - Could be implemented as a Grafana dashboard

3. **Service Health Checks**:
   - Monitor Grafana data source status
   - Alert on GitHub API errors in logs

## Future Enhancements

### GitHub App Authentication

For fully automated token rotation, we can migrate to GitHub App authentication:

**Benefits**:
- Automatic short-lived tokens (1 hour expiration)
- No manual rotation needed
- Better audit trail
- Per-installation permissions

**Implementation**:
1. Create GitHub App at https://github.com/settings/apps/new
2. Install app on `symmatree` organization
3. Store App credentials (ID, installation ID, PEM key) in 1Password
4. Update Terraform provider to use `app_auth` block
5. Provider automatically generates installation tokens

**Migration Path**:
1. Create and configure GitHub App
2. Test with non-critical service first
3. Gradually migrate all services
4. Deprecate manual PAT workflow

See [GitHub Provider App Auth Documentation](https://registry.terraform.io/providers/integrations/github/latest/docs#github-app-installation-configuration) for details.

## Troubleshooting

### Token Not Syncing to Kubernetes

1. **Check 1Password Operator logs**:
   ```bash
   kubectl logs -n onepassword -l app.kubernetes.io/name=onepassword-operator
   ```

2. **Verify OnePasswordItem resource**:
   ```bash
   kubectl describe onepassworditem github-data-source-secret -n grafana
   ```

3. **Check operator has vault access**:
   ```bash
   # Verify service account token is valid
   kubectl get secret onepassword-token -n onepassword
   ```

### Terraform Apply Fails with Authentication Error

1. **Verify token is valid**:
   ```bash
   # Test token with GitHub API
   curl -H "Authorization: token $TF_VAR_github_token" \
     https://api.github.com/user
   ```

2. **Check token permissions**:
   - Go to https://github.com/settings/tokens?type=beta
   - Verify token has required scopes
   - Ensure token hasn't expired

3. **Verify token repository access**:
   ```bash
   # Test access to tiles repo
   curl -H "Authorization: token $TF_VAR_github_token" \
     https://api.github.com/repos/symmatree/tiles
   ```

### Service Not Restarting After Rotation

1. **Check auto-restart annotation**:
   ```bash
   kubectl get onepassworditem <item-name> -n <namespace> -o yaml | \
     grep -A2 annotations
   ```

2. **Manually trigger restart**:
   ```bash
   kubectl rollout restart deployment <deployment-name> -n <namespace>
   ```

3. **Check operator deployment restart feature**:
   ```bash
   # Ensure operator supports auto-restart (v1.8.0+)
   kubectl get deployment onepassword-operator -n onepassword -o yaml | \
     grep image
   ```

## References

- [GitHub Fine-Grained PAT Documentation](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)
- [1Password Operator Auto-Restart Guide](https://github.com/1Password/onepassword-operator/blob/main/USAGEGUIDE.md#configuring-automatic-rolling-restarts-of-deployments)
- [Terraform GitHub Provider](https://registry.terraform.io/providers/integrations/github/latest/docs)
- [Tiles Config Propagation Documentation](./config-propagation.md)
- [Tiles Secrets Management](./secrets.md)
