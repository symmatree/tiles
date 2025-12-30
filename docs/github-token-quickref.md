# GitHub Token Quick Reference

Quick reference for common GitHub token operations.

## Check Token Expiration

```bash
# View token metadata
op item get "github-tiles-tf-bootstrap" --vault tiles-secrets --fields label=last_rotated,label=expiration_days

# Calculate expiration date (last_rotated + expiration_days)
```

## Rotate a Token

```bash
# 1. Generate new token at https://github.com/settings/tokens?type=beta
#    - Set expiration to 90 days
#    - Configure permissions as documented in github-token-rotation.md

# 2. Apply via Terraform
cd tf/bootstrap
export TF_VAR_onepassword_sa_token=$(op read op://tiles-secrets/tiles-onepassword-sa/credential)
export TF_VAR_github_token="github_pat_NEW_TOKEN_HERE"
terraform apply

# 3. Verify (pods with auto-restart should restart automatically)
kubectl get pods -n grafana -w
```

## Check Token in Kubernetes

```bash
# View the OnePasswordItem
kubectl get onepassworditem github-data-source-secret -n grafana -o yaml

# View the actual secret (base64 encoded)
kubectl get secret github-data-source-secret -n grafana -o yaml

# Decode and verify token
kubectl get secret github-data-source-secret -n grafana -o jsonpath='{.data.password}' | base64 -d
```

## Test Token Validity

```bash
# Test terraform bootstrap token
curl -H "Authorization: token $(op read op://tiles-secrets/github-tiles-tf-bootstrap/password)" \
  https://api.github.com/repos/symmatree/tiles

# Test Grafana token
curl -H "Authorization: token $(op read op://tiles-secrets/grafana-github-token/password)" \
  https://api.github.com/repos/symmatree/tiles
```

## Force Pod Restart

If auto-restart doesn't trigger:

```bash
# Restart Grafana
kubectl rollout restart deployment grafana -n grafana

# Check restart status
kubectl rollout status deployment grafana -n grafana
```

## Emergency: Token Expired

```bash
# 1. Generate new token immediately
# 2. Apply via Terraform (as shown in "Rotate a Token" above)
# 3. Manual restart of affected services
kubectl rollout restart deployment grafana -n grafana
# 4. Verify services are working
```

## View All GitHub Token Items

```bash
# List all items with "github" in the name
op item list --vault tiles-secrets | grep github

# Get details of all GitHub tokens
op item get "github-tiles-tf-bootstrap" --vault tiles-secrets
op item get "grafana-github-token" --vault tiles-secrets
```

## Verify Auto-Restart Configuration

```bash
# Check if auto-restart annotation is present
kubectl get onepassworditem github-data-source-secret -n grafana -o jsonpath='{.metadata.annotations.operator\.1password\.io/auto-restart}'

# Should output: true
```

## Check 1Password Operator Status

```bash
# View operator pods
kubectl get pods -n onepassword

# View operator logs
kubectl logs -n onepassword -l app.kubernetes.io/name=onepassword-operator --tail=50

# Check operator sync status
kubectl get onepassworditem -A
```

## Common Issues

### "Token has expired or been revoked"
- Generate new token
- Apply via Terraform
- Wait for automatic restart or trigger manually

### "Permission denied" errors
- Verify token has correct permissions (see rotation guide)
- Check repository access is set to `symmatree/tiles`
- Regenerate token with correct permissions

### Secret not syncing to Kubernetes
- Check 1Password operator is running: `kubectl get pods -n onepassword`
- View operator logs for errors
- Verify OnePasswordItem resource exists and has correct itemPath

## Full Documentation

For detailed procedures and troubleshooting:
- **Rotation Guide**: `docs/github-token-rotation.md`
- **Migration Guide**: `docs/github-token-migration.md`
- **Module README**: `tf/modules/github-app-token/README.md`
