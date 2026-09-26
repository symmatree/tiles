# GCP Enterprise Foundation Setup

Implements a lightweight GCP enterprise foundation inspired by the [GCP Security Foundations Blueprint](https://docs.cloud.google.com/architecture/blueprints/security-foundations).

## Projects Created

The bootstrap creates four GCP projects:

- **tiles-id**: Workload identity pool for GitHub Actions OIDC authentication
- **tiles-kms**: Centralized KMS for secrets management
- **tiles-main**: Per-environment resources for prod (buckets, DNS, service accounts)
- **tiles-test-main**: Per-environment resources for test

Each project has:
- Random project ID suffix
- $10/month budget with 50% and 100% alerts
- Essential contacts configured
- Owner role granted to tiles-owner@googlegroups.com group
- Billing account inherited from seed project (symm-custodes)

## Prerequisites

1. **Google Group**: Create `tiles-owner@googlegroups.com` and add yourself as a member
2. **Permissions**: You need Owner role on symm-custodes project (already have this)

## Apply Bootstrap

```bash
cd tf/bootstrap
terraform init
terraform plan
terraform apply
```

This creates the projects, sets up workload identity, and publishes the OIDC provider name and service account email as the `WORKLOAD_IDENTITY_PROVIDER` and `SERVICE_ACCOUNT_EMAIL` repository variables, which is what the workflows read. Neither is a secret; the pool's `attribute_condition` is what restricts it.

## Workload Identity

GitHub workflows now authenticate via OIDC instead of service account keys. The `tiles-terraform-oidc` service account has necessary permissions across all projects.

## References

- [GCP Security Foundations Blueprint](https://docs.cloud.google.com/architecture/blueprints/security-foundations)
- [Terraform Google Project Factory](https://registry.terraform.io/modules/terraform-google-modules/project-factory/google/latest)
- [GitHub OIDC Module](https://registry.terraform.io/modules/terraform-google-modules/github-actions-runners/google/latest/submodules/gh-oidc)
