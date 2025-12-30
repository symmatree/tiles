# GitHub Token Rotation - Migration Guide

This guide helps you migrate from the old manual GitHub token management to the new Terraform-managed workflow.

## What's Changing?

**Before**: GitHub tokens were manually created and stored in 1Password without metadata or tracking.

**After**: GitHub tokens are managed through Terraform, stored in 1Password with metadata (expiration, permissions, last rotation), and automatically propagated to Kubernetes services.

## Benefits of the New System

1. **Structured token management**: Tokens are stored with metadata (expiration date, permissions, usage)
2. **Automatic propagation**: 1Password Operator syncs tokens to Kubernetes and triggers restarts
3. **Clear rotation workflow**: Documented process for creating and rotating tokens every 90 days
4. **Better tracking**: Know when tokens were last rotated and when they need renewal
5. **Recovery procedures**: Clear steps if rotation is missed or tokens expire

## Migration Steps

### Step 1: Generate New Fine-Grained PATs

Create two new fine-grained Personal Access Tokens on GitHub:

#### Token 1: Terraform Bootstrap
- **Name**: `Tiles Terraform Bootstrap - 2025-Q1` (update quarter as needed)
- **Expiration**: 90 days
- **Repository access**: `symmatree/tiles`
- **Permissions**:
  - Repository permissions:
    - Administration: Read and write
    - Contents: Read and write
    - Metadata: Read-only (mandatory)
    - Secrets: Read and write
    - Workflows: Read and write

Go to: https://github.com/settings/tokens?type=beta

#### Token 2: Grafana/Monitoring (Optional - can use same token initially)
- **Name**: `Tiles Grafana GitHub - 2025-Q1`
- **Expiration**: 90 days
- **Repository access**: `symmatree/tiles`
- **Permissions**:
  - Repository permissions:
    - Contents: Read-only
    - Issues: Read-only
    - Metadata: Read-only (mandatory)
    - Pull requests: Read-only

### Step 2: Apply Tokens via Terraform

```bash
cd tf/bootstrap

# Export 1Password service account token
export TF_VAR_onepassword_sa_token=$(op read op://tiles-secrets/tiles-onepassword-sa/credential)

# Export the new GitHub token
export TF_VAR_github_token="github_pat_YOUR_NEW_TOKEN_HERE"

# Review the plan
terraform plan

# Apply changes (this will update 1Password with new tokens and metadata)
terraform apply
```

### Step 3: Verify 1Password Storage

```bash
# Verify both tokens are now managed by Terraform
op item get "github-tiles-tf-bootstrap" --vault tiles-secrets
op item get "grafana-github-token" --vault tiles-secrets

# Check metadata fields
op item get "github-tiles-tf-bootstrap" --vault tiles-secrets --fields label=last_rotated
op item get "github-tiles-tf-bootstrap" --vault tiles-secrets --fields label=expiration_days
```

### Step 4: Verify Kubernetes Sync (if cluster is running)

If you have a running Kubernetes cluster with the 1Password Operator installed:

```bash
# Check that the secret was synced
kubectl get secret github-data-source-secret -n grafana

# Verify the OnePasswordItem has auto-restart annotation
kubectl get onepassworditem github-data-source-secret -n grafana -o yaml | grep -A2 annotations

# Check if Grafana pod restarted (may take a few minutes)
kubectl get pods -n grafana
```

### Step 5: Remove Old Token References

The old tokens from tales-secrets have been migrated. If you have any local scripts or tools still using the old token references, update them:

**Old**:
```bash
TOKEN=$(op read op://tales-secrets/jupyterhub-github-token/password)
```

**New**:
```bash
TOKEN=$(op read op://tiles-secrets/grafana-github-token/password)
```

The mimir webhook build script has already been updated in this PR.

### Step 6: Set Up Rotation Reminder

Set a calendar reminder for **7 days before** your token expires (83 days from creation):

1. Create a recurring calendar event every 90 days
2. Set reminder 7 days before the event
3. Include link to rotation guide: `docs/github-token-rotation.md`
4. Add note with command: `export TF_VAR_github_token="<new_token>" && cd tf/bootstrap && terraform apply`

## Troubleshooting Migration

### Issue: Terraform plan shows changes to existing resources

**Expected behavior**: Terraform should only show additions of the new token management modules. Existing GitHub repository configuration should remain unchanged.

**If you see unexpected changes**: Review the diff carefully. The new modules only manage the 1Password storage of tokens, not the GitHub provider authentication itself.

### Issue: 1Password Operator not syncing to Kubernetes

**Check 1**: Verify operator is running:
```bash
kubectl get pods -n onepassword
```

**Check 2**: Verify operator logs:
```bash
kubectl logs -n onepassword -l app.kubernetes.io/name=onepassword-operator
```

**Check 3**: Verify OnePasswordItem resource exists:
```bash
kubectl get onepassworditem -A
```

**Fix**: Ensure the 1Password service account token used by the operator has access to the tiles-secrets vault.

### Issue: Grafana can't access GitHub data source

**Check 1**: Verify secret exists and has correct data:
```bash
kubectl get secret github-data-source-secret -n grafana -o yaml
```

**Check 2**: Verify token has correct permissions:
```bash
# Test token manually
curl -H "Authorization: token $(op read op://tiles-secrets/grafana-github-token/password)" \
  https://api.github.com/repos/symmatree/tiles
```

**Fix**: If token is invalid, generate a new one and re-apply Terraform.

## Rollback Procedure

If you need to rollback to the old manual token management:

1. **Remove the new modules from github.tf**:
   ```bash
   git revert <commit-hash>
   ```

2. **Manually update 1Password items** to remove Terraform metadata:
   - Edit items in 1Password UI
   - Remove the "metadata" section

3. **Update references** back to old token names if needed

Note: Rollback is not recommended as the new system provides better tracking and automation.

## Next Steps After Migration

1. **Review the rotation guide**: Read `docs/github-token-rotation.md` thoroughly
2. **Test rotation process**: In ~83 days, practice rotating the tokens
3. **Plan for GitHub App migration**: Consider setting up a GitHub App for fully automated token rotation (see guide for details)
4. **Monitor token usage**: Keep track of which services use GitHub tokens and ensure they all have auto-restart enabled

## Getting Help

- **Documentation**: `docs/github-token-rotation.md` - Complete rotation guide
- **Module README**: `tf/modules/github-app-token/README.md` - Technical details
- **Secrets guide**: `docs/secrets.md` - General secrets management
- **Config propagation**: `docs/config-propagation.md` - How configs flow through the system

For issues or questions, open a GitHub issue in the tiles repository.
