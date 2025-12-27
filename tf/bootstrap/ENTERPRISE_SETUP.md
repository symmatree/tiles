# GCP Enterprise Foundation Setup

This directory contains Terraform configuration for setting up a mini enterprise foundation on Google Cloud Platform, inspired by the [GCP Security Foundations Blueprint](https://docs.cloud.google.com/architecture/blueprints/security-foundations).

## Architecture

The setup creates the following GCP projects:

- **tiles-id**: Workload identity project for GitHub Actions OIDC authentication
- **tiles-kms**: Centralized KMS for secrets management
- **tiles-main**: Per-environment project for prod environment resources
- **tiles-test-main**: Per-environment project for test environment resources

Each project is configured with:
- Random project ID suffix for uniqueness
- $10 monthly budget with alerts at 50% and 100%
- Essential contacts for notifications
- Owner role granted to tiles-owner Google group
- Minimal required APIs enabled

## Prerequisites

### 1. Google Cloud Setup

1. **Billing Account**: You need a GCP billing account ID. Find yours at: https://console.cloud.google.com/billing
2. **Organization** (Optional): If you have a GCP organization, note the organization ID
3. **Google Group**: Create a Google Group named "tiles-owner" at https://groups.google.com/
   - Use the email address specified in `tiles_owner_group_email` variable
   - Add the user specified in `gcp_essential_contacts_email` as a member
4. **Required Permissions**: You need the following permissions to run this bootstrap:
   - Billing Account User on the billing account
   - Project Creator (or Organization Admin if using an organization)
   - Ability to grant IAM roles on projects

### 2. Configuration

Update `tiles.auto.tfvars` with your values:

```hcl
# Replace REPLACE_WITH_YOUR_BILLING_ACCOUNT_ID with your actual billing account ID
gcp_billing_account_id = "012345-6789AB-CDEFGH"

# Optionally uncomment and set if using an organization
# gcp_organization_id = "123456789012"

# Optionally uncomment and set if using a folder
# gcp_folder_id = "123456789012"
```

## Initial Bootstrap

### Step 1: Apply Bootstrap Terraform

```bash
cd tf/bootstrap

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration (creates projects and workload identity)
terraform apply
```

This will:
1. Create the four GCP projects
2. Set up budgets and IAM policies
3. Create a workload identity pool for GitHub Actions
4. Store the workload identity credentials in 1Password

### Step 2: Verify 1Password Secret

After applying, verify that the `gh_oidc_workload_identity` secret was created in your 1Password vault `tiles-secrets`. It should contain:
- `workload_identity_provider`: The full provider name
- `service_account_email`: The service account email for GitHub Actions

### Step 3: Update GitHub Workflows

The GitHub workflows have been updated to use OIDC authentication instead of service account keys:
- `.github/workflows/bootstrap-cluster.yaml`
- `.github/workflows/nodes-plan-apply.yaml`

These workflows now use the `google-github-actions/auth@v2` action with workload identity federation.

## Workload Identity Setup

The workload identity pool is configured to allow GitHub Actions from the `symmatree/tiles` repository to authenticate as the `tiles-terraform-oidc` service account.

The service account has the following permissions:
- **tiles-id project**: Viewer
- **tiles-kms project**: Cloud KMS Admin
- **tiles-main project**: Editor, Storage Admin, DNS Admin
- **tiles-test-main project**: Editor, Storage Admin, DNS Admin
- **symm-custodes project** (seed): Editor, Storage Admin, DNS Admin (for backwards compatibility)

## Security Considerations

1. **No Service Account Keys**: The setup uses OIDC-based workload identity federation, eliminating the need to manage service account keys.
2. **Least Privilege**: Each project has minimal APIs enabled and the service account has only necessary permissions.
3. **Budget Alerts**: All projects have budget alerts to prevent unexpected costs.
4. **Essential Contacts**: Critical notifications are sent to the configured email address.

## Maintenance

### Adding New Projects

To add new projects, follow the pattern in `gcp-projects.tf`:
1. Use the `terraform-google-modules/project-factory/google` module
2. Set `random_project_id = true`
3. Configure budgets with `budget_amount` and `budget_alert_spent_percents`
4. Add essential contacts
5. Grant Owner role to tiles-owner group
6. Add necessary IAM permissions for the terraform OIDC service account in `gcp-workload-identity.tf`

### Updating Service Account Permissions

Update `gcp-workload-identity.tf` to add or modify IAM roles for the `tiles-terraform-oidc` service account.

## Troubleshooting

### Organization Not Found

If you don't have a GCP organization, leave `gcp_organization_id` empty (the default). Projects will be created without an organization.

### Budget API Not Enabled

If you get an error about the Billing Budget API, enable it manually:
```bash
gcloud services enable billingbudgets.googleapis.com --project=PROJECT_ID
```

### Essential Contacts API Not Enabled

If you get an error about the Essential Contacts API, enable it manually:
```bash
gcloud services enable essentialcontacts.googleapis.com --project=PROJECT_ID
```

### Workload Identity Not Working

1. Verify the workload identity pool and provider were created in the tiles-id project
2. Check that the service account has the Workload Identity User role
3. Ensure the GitHub repository name matches `symmatree/tiles`
4. Verify the 1Password secret contains the correct provider name and service account email

## References

- [GCP Security Foundations Blueprint](https://docs.cloud.google.com/architecture/blueprints/security-foundations)
- [Terraform Google Project Factory](https://registry.terraform.io/modules/terraform-google-modules/project-factory/google/latest)
- [GitHub OIDC Module](https://registry.terraform.io/modules/terraform-google-modules/github-actions-runners/google/latest/submodules/gh-oidc)
- [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)
