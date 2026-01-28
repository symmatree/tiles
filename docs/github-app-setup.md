# GitHub App Setup and Token Management

This guide explains how to set up a GitHub App for automated GitHub token generation in the Tiles infrastructure.

## Why GitHub Apps?

GitHub Apps provide several advantages over Personal Access Tokens (PATs):

1. **Programmatic Token Generation**: Apps can generate installation tokens via API
2. **Short-Lived Tokens**: Installation tokens expire after 1 hour (automatic security)
3. **No Manual Rotation**: Terraform automatically refreshes tokens on each apply
4. **Fine-Grained Permissions**: Precise control over what the app can access
5. **Better Audit Trail**: All actions are attributed to the app, not a user
6. **Scalable**: One app can serve multiple repositories/organizations

## Creating a GitHub App

### Step 1: Create the App

1. Go to your GitHub organization settings: https://github.com/organizations/symmatree/settings/apps
2. Click "New GitHub App"
3. Fill in the form:

   **Basic Information:**
   - **GitHub App name**: `tiles-terraform-automation` (or similar)
   - **Description**: `Terraform automation for Tiles infrastructure`
   - **Homepage URL**: `https://github.com/symmatree/tiles`
   
   **Webhook:**
   - ❌ Uncheck "Active" (we don't need webhooks)
   
   **Permissions:**
   
   *Repository permissions:*
   - Administration: Read and write
   - Contents: Read and write  
   - Metadata: Read-only (mandatory)
   - Secrets: Read and write
   - Workflows: Read and write
   - Pull requests: Read-only (for Grafana)
   - Issues: Read-only (for Grafana)
   
   **Where can this GitHub App be installed?**
   - ◉ Only on this account

4. Click "Create GitHub App"

### Step 2: Generate Private Key

1. After creation, scroll down to "Private keys"
2. Click "Generate a private key"
3. A `.pem` file will download - **save this securely!**
4. Note the **App ID** displayed at the top of the page

### Step 3: Install the App

1. Go to "Install App" in the left sidebar
2. Click "Install" next to your organization
3. Choose repositories:
   - ◉ Only select repositories
   - Select: `symmatree/tiles`
4. Click "Install"
5. Note the **Installation ID** from the URL (e.g., `https://github.com/settings/installations/12345678`)

### Step 4: Store Credentials in 1Password

Create a new Password item in the `tiles-secrets` vault:

```bash
cd tf/bootstrap

# Read the PEM file content
PEM_CONTENT=$(cat ~/Downloads/tiles-terraform-automation.*.private-key.pem)

# Create 1Password item
op item create \
  --vault tiles-secrets \
  --category password \
  --title "github-app-tiles-tf" \
  password="$PEM_CONTENT" \
  app_details.app_id="YOUR_APP_ID" \
  app_details.installation_id="YOUR_INSTALLATION_ID" \
  metadata.description="GitHub App credentials for Terraform provider" \
  metadata.source="manually created"
```

Or manually via 1Password UI:
- **Title**: `github-app-tiles-tf`
- **Password**: (paste PEM file content)
- **Section "app_details"**:
  - `app_id`: Your App ID
  - `installation_id`: Your Installation ID
- **Section "metadata"**:
  - `description`: GitHub App credentials for Terraform provider
  - `source`: manually created

## Using the GitHub App with Terraform

### Terraform Configuration

The terraform configuration in `tf/bootstrap/github.tf` already supports GitHub App authentication. Set the environment variables:

```bash
cd tf/bootstrap

# Export App credentials from 1Password
export TF_VAR_github_app_id=$(op read op://tiles-secrets/github-app-tiles-tf/app_details/app_id)
export TF_VAR_github_app_installation_id=$(op read op://tiles-secrets/github-app-tiles-tf/app_details/installation_id)
export TF_VAR_github_app_pem_file=$(op read op://tiles-secrets/github-app-tiles-tf/password)
export TF_VAR_github_owner="symmatree"

# DO NOT set TF_VAR_github_token (leave it empty to use App authentication)

# Run Terraform
terraform plan
terraform apply
```

The provider will automatically:
- Generate a short-lived installation token
- Use that token for GitHub API calls
- Refresh the token on each terraform run

## Service Token Generation for Grafana

For services like Grafana that need standalone tokens (not directly managed by Terraform), we use a CronJob that runs the token generation script.

### Implementation in Kubernetes

The token refresh is implemented as a Kubernetes CronJob. See `.github/workflows/bootstrap-cluster.yaml` for the actual implementation pattern.

The workflow:
1. Loads GitHub App credentials from 1Password (similar to how it loads `TILES_VPN_CONFIG`)
2. Runs the token generation script
3. Script stores the generated token in 1Password
4. 1Password Operator syncs the token to Kubernetes secrets
5. Grafana pods automatically restart (via `operator.1password.io/auto-restart: "true"` annotation)

### 1Password Credentials for Token Refresher

The CronJob needs access to 1Password to:
1. Read GitHub App credentials
2. Write the generated token back to 1Password

This uses the existing 1Password service account that's already configured for the cluster. The service account token is available as a Kubernetes secret and can be used by the CronJob.

Reference the existing pattern in workflows like `nodes-plan-apply.yaml` which uses:
```yaml
env:
  OP_SERVICE_ACCOUNT_TOKEN: ${{ secrets.ONEPASSWORD_SA_TOKEN }}
  SOME_SECRET: "op://tiles-secrets/item-name/field"
```

## Updating CI/CD Workflows

Update `.github/workflows/` to use GitHub App credentials. Example for `nodes-plan-apply.yaml`:

```yaml
- name: Load GitHub App credentials
  uses: 1password/load-secrets-action@v3
  env:
    OP_SERVICE_ACCOUNT_TOKEN: ${{ secrets.ONEPASSWORD_SA_TOKEN }}
    GITHUB_APP_ID: "op://tiles-secrets/github-app-tiles-tf/app_details/app_id"
    GITHUB_APP_INSTALLATION_ID: "op://tiles-secrets/github-app-tiles-tf/app_details/installation_id"
    GITHUB_APP_PEM_FILE: "op://tiles-secrets/github-app-tiles-tf/password"

- name: Run Terraform
  env:
    TF_VAR_github_app_id: ${{ env.GITHUB_APP_ID }}
    TF_VAR_github_app_installation_id: ${{ env.GITHUB_APP_INSTALLATION_ID }}
    TF_VAR_github_app_pem_file: ${{ env.GITHUB_APP_PEM_FILE }}
    TF_VAR_github_owner: "symmatree"
  run: |
    cd tf/bootstrap
    terraform plan
    terraform apply -auto-approve
```

## Troubleshooting

### "Bad credentials" error

- **Check App ID**: Ensure `GITHUB_APP_ID` is correct
- **Check Installation ID**: Ensure `GITHUB_APP_INSTALLATION_ID` is correct
- **Check PEM format**: Ensure the private key is valid and properly formatted
- **Check permissions**: Ensure the App has required permissions
- **Check installation**: Ensure the App is installed on the correct repos

### "Resource not accessible by integration" error

The App doesn't have the required permissions:
1. Go to App settings
2. Update permissions
3. Organization owner must approve the permission change
4. Reinstall the App if needed

### Token generation script fails

- **Missing tools**: Ensure `jq`, `openssl`, `curl` are installed
- **PEM format**: Check the private key format is correct
- **Time sync**: Ensure system time is accurate (JWT validation is time-sensitive)

### Terraform can't authenticate

```bash
# Debug: Check if variables are set
echo "App ID: $TF_VAR_github_app_id"
echo "Installation ID: $TF_VAR_github_app_installation_id"
echo "PEM length: ${#TF_VAR_github_app_pem_file}"

# Verify PEM file starts with correct header
echo "$TF_VAR_github_app_pem_file" | head -n1
# Should output: -----BEGIN RSA PRIVATE KEY-----
```

## Key Rotation

To rotate the GitHub App private key:

1. Go to GitHub App settings
2. Generate a new private key
3. Update the 1Password item with the new PEM content
4. The change will automatically propagate to all workflows and services on their next run

Since tokens are short-lived (1 hour), there's minimal risk during the transition period.

## References

- [GitHub Apps Documentation](https://docs.github.com/en/apps)
- [Authenticating as a GitHub App](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app)
- [GitHub App Permissions](https://docs.github.com/en/rest/authentication/permissions-required-for-github-apps)
- [Terraform GitHub Provider app_auth](https://registry.terraform.io/providers/integrations/github/latest/docs#github-app-installation-configuration)
