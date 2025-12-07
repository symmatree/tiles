# Environment Strategy: Test and Production Parallel Environments

## Overview

This document describes the strategy for managing two parallel Terraform environments (test and production) with a tag-based deployment workflow, while maintaining side-by-side configuration files for easy comparison and review in pull requests.

## Current State

The repository currently implements:

- Terraform workspaces (`test` and `prod`) in `tf/nodes` directory
- Test environment active (`tiles-test` cluster)
- Production environment ready (`tiles` cluster)
- Separate state files per workspace in GCS backend
- Tag-based deployment workflow (`test` and `prod` tags)
- Automatic tag pushing when deploying to environments
- Automatic deployment on push to `main` branch (deploys to test)
- Manual deployment via `workflow_dispatch` with environment selection
- Composite actions for modular workflow steps
- PR planning for both test and prod environments

## Architecture

### Architecture Principles

1. **Parallel Environments**: Test and production are managed as separate Terraform workspaces
2. **Shared Bootstrap**: The bootstrap Terraform (`tf/bootstrap`) remains shared since it initializes resources for both environments
3. **Side-by-Side Configuration**: Both environment configurations live in the same source tree for easy diffing in PRs
4. **Tag-Based Deployment**: Git tags (`test` and `prod`) track what's deployed and trigger redeployments
5. **Promotion Workflow**: Production deployments can be promoted from test-tagged commits or deployed directly
6. **Shared Code, Different Variables**: Most differences between environments are represented as different `.auto.tfvars` files

### Directory Structure

```
tf/
├── bootstrap/          # Shared bootstrap (unchanged)
│   └── ...
├── nodes-test/         # Test environment configuration
│   ├── main.tf         # Shared provider setup
│   ├── terraform.tfvars
│   ├── test.tfvars     # Test-specific overrides
│   ├── cluster.tf      # Cluster module instantiation
│   └── outputs.tf
└── nodes-prod/         # Production environment configuration
    ├── main.tf         # Shared provider setup (symlinked or shared module)
    ├── terraform.tfvars
    ├── prod.tfvars     # Prod-specific overrides
    ├── cluster.tf      # Cluster module instantiation
    └── outputs.tf
```

**Alternative Structure (Single Directory with Workspaces):**

```
tf/
├── bootstrap/
└── nodes/
    ├── main.tf                   # Shared provider setup
    ├── terraform.tfvars          # Shared defaults
    ├── test.auto.tfvars          # Test-specific (auto-loaded for test workspace)
    ├── prod.auto.tfvars          # Prod-specific (auto-loaded for prod workspace)
    ├── cluster-test.tf           # Test cluster module (conditional)
    ├── cluster-prod.tf           # Prod cluster module (conditional)
    ├── test-vms.tf               # Test VM definitions
    ├── prod-vms.tf               # Prod VM definitions
    ├── variables.tf
    ├── outputs.tf
    └── versions.tf
```

**Questions:**

- **Q1**: Which structure do you prefer? Separate directories (`nodes-test/`, `nodes-prod/`) or single directory with Terraform workspaces?

A: Workspaces

- **Q2**: Should `main.tf` (provider setup) be duplicated, symlinked, or extracted to a shared module?

A: Workspaces so same file

## Terraform Workspaces Deep Dive

### Quick Answer: Pre-Creation Not Required

**Do you need to pre-create workspaces or state files?** No.

- Workspaces are created automatically with `terraform workspace new <name>`
- State files are created automatically in GCS when you first run `terraform apply` in a workspace
- The get-or-create pattern (`terraform workspace select test || terraform workspace new test`) is idempotent and safe
- GCS bucket and prefix are all that's needed - Terraform handles workspace subdirectories automatically

**State paths are automatic:**

- Backend prefix: `terraform/tiles/nodes` (configured once in `versions.tf`)
- Test workspace state: `gs://custodes-tf-state/terraform/tiles/nodes/test/default.tfstate` (created automatically)
- Prod workspace state: `gs://custodes-tf-state/terraform/tiles/nodes/prod/default.tfstate` (created automatically)

### How Workspaces Work

Terraform workspaces are a built-in feature that allows you to maintain multiple state files for the same configuration. Each workspace has its own isolated state, but they share the same Terraform code.

**Key Concepts:**

- **Workspace**: A named context that isolates state (like `test` or `prod`)
- **State Isolation**: Each workspace has its own state file in the backend
- **Code Sharing**: All workspaces use the same `.tf` files
- **Variable Overrides**: Use `.auto.tfvars` files that are workspace-specific

### Directory Structure with Workspaces

```
tf/nodes/
├── main.tf                    # Providers, data sources (shared)
├── variables.tf               # Variable definitions (shared)
├── versions.tf               # Backend config (shared, workspace-aware)
├── terraform.tfvars          # Shared defaults for both environments
├── test.auto.tfvars          # Auto-loaded when workspace=test
├── prod.auto.tfvars          # Auto-loaded when workspace=prod
├── cluster-test.tf           # Test cluster module
├── cluster-prod.tf           # Prod cluster module
├── test-vms.tf               # Test VM local values
├── prod-vms.tf               # Prod VM local values
├── proxmox-nodes.tf          # Shared Proxmox node handling
├── talos-schematic.tf        # Shared Talos schematic
└── outputs.tf                # Outputs (can be workspace-aware)
```

### Backend Configuration

The backend configuration remains the same - Terraform automatically appends the workspace name to the state path:

```hcl
# versions.tf
terraform {
  backend "gcs" {
    bucket = "custodes-tf-state"
    prefix = "terraform/tiles/nodes"  # Workspace name appended automatically
  }
}
```

**State File Locations (Automatic):**

- Test workspace: `gs://custodes-tf-state/terraform/tiles/nodes/test/default.tfstate`
- Prod workspace: `gs://custodes-tf-state/terraform/tiles/nodes/prod/default.tfstate`

**Important:** You do NOT need to pre-create workspaces or state files. Terraform automatically:

- Creates the workspace when you first use `terraform workspace new <name>`
- Creates the state file in GCS when you first run `terraform apply` in that workspace
- The GCS bucket and prefix path are all that's needed - Terraform handles the workspace subdirectory automatically

### Workspace Commands

```bash
# List workspaces
terraform workspace list

# Create/select test workspace (get-or-create pattern)
terraform workspace select test || terraform workspace new test

# Create/select prod workspace (get-or-create pattern)
terraform workspace select prod || terraform workspace new prod

# Show current workspace
terraform workspace show

# Delete a workspace (after destroying resources)
terraform workspace delete test
```

**Get-or-Create Pattern Explained:**

- `terraform workspace select test` tries to switch to the `test` workspace
- If it doesn't exist, the command fails (non-zero exit code)
- The `||` operator means "if the previous command failed, run this instead"
- `terraform workspace new test` creates the workspace if it didn't exist
- This pattern is idempotent: safe to run multiple times, works whether workspace exists or not

### Variable Loading with Workspaces

Terraform automatically loads `.auto.tfvars` files. The naming convention `{workspace}.auto.tfvars` means:

- When `workspace = test`: Loads `test.auto.tfvars` automatically
- When `workspace = prod`: Loads `prod.auto.tfvars` automatically

**Example files:**

```hcl
# terraform.tfvars (shared)
onepassword_vault_name = "tiles-secrets"
proxmox_storage_iso    = "local"
talos_version          = "1.11.5"
project_id             = "symm-custodes"
gcp_region             = "us-east1"

# test.auto.tfvars
cluster_name        = "tiles-test"
external_ip_cidr    = "10.0.193.0/24"
pod_cidr            = "10.0.208.0/20"
service_cidr        = "10.0.200.0/21"
control_plane_vip   = "10.0.192.10"
start_vms           = true
apply_configs       = true
run_bootstrap       = true

# prod.auto.tfvars
cluster_name        = "tiles"
external_ip_cidr    = "10.0.129.0/24"
pod_cidr            = "10.0.144.0/20"
service_cidr        = "10.0.136.0/21"
control_plane_vip   = "10.0.128.10"
start_vms           = false
apply_configs       = true
run_bootstrap       = false
```

### Conditional Resource Creation

Since both environments share the same code, you need to conditionally create resources:

**Option 1: Using `terraform.workspace`**

```hcl
# cluster-test.tf
module "tiles-test" {
  count = terraform.workspace == "test" ? 1 : 0
  source = "../modules/talos-cluster"
  cluster_name = "tiles-test"
  # ... other config
}

# cluster-prod.tf
module "tiles-prod" {
  count = terraform.workspace == "prod" ? 1 : 0
  source = "../modules/talos-cluster"
  cluster_name = "tiles"
  # ... other config
}
```

**Option 2: Using a single module with workspace-based locals**

```hcl
# cluster.tf
locals {
  cluster_config = terraform.workspace == "test" ? {
    cluster_name = "tiles-test"
    vms = local.test_vms
    # ... test config
  } : {
    cluster_name = "tiles"
    vms = local.prod_vms
    # ... prod config
  }
}

module "cluster" {
  source = "../modules/talos-cluster"
  cluster_name = local.cluster_config.cluster_name
  vms = local.cluster_config.vms
  # ...
}
```

### GitHub Actions Workflow with Workspaces

**Key Points:**

- Workspaces are created automatically - no pre-creation needed
- State files are created automatically in GCS when first applied
- The get-or-create pattern (`select || new`) is idempotent and safe

```yaml
jobs:
  deploy-test:
    steps:
      - uses: actions/checkout@v6
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.13.3"

      - name: Create/update test tag
        run: |
          git tag -f test HEAD
          git push -f origin test

      - name: Terraform init
        working-directory: tf/nodes
        run: terraform init

      - name: Select or create test workspace
        working-directory: tf/nodes
        run: terraform workspace select test || terraform workspace new test

      - name: Terraform plan
        working-directory: tf/nodes
        run: terraform plan -lock-timeout=5m -input=false

      - name: Terraform apply
        working-directory: tf/nodes
        run: terraform apply -lock-timeout=5m -auto-approve

  deploy-prod:
    steps:
      - uses: actions/checkout@v6
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.13.3"

      - name: Find test tag commit
        id: test-tag
        run: |
          TEST_COMMIT=$(git rev-list -n 1 test)
          echo "commit=${TEST_COMMIT}" >> $GITHUB_OUTPUT
          git checkout ${TEST_COMMIT}

      - name: Create/update prod tag
        run: |
          git tag -f prod ${{ steps.test-tag.outputs.commit }}
          git push -f origin prod

      - name: Terraform init
        working-directory: tf/nodes
        run: terraform init

      - name: Select or create prod workspace
        working-directory: tf/nodes
        run: terraform workspace select prod || terraform workspace new prod

      - name: Terraform plan
        working-directory: tf/nodes
        run: terraform plan -lock-timeout=5m -input=false

      - name: Terraform apply
        working-directory: tf/nodes
        run: terraform apply -lock-timeout=5m -auto-approve
```

**State Path Details:**

- After `terraform init`, Terraform knows about the backend
- When you select/create a workspace, Terraform will use that workspace name in the state path
- The state file path is: `gs://custodes-tf-state/terraform/tiles/nodes/{workspace}/default.tfstate`
- No manual GCS operations needed - Terraform handles everything automatically

### Pros of Workspaces

1. **Single Source of Truth**: All code in one place, easier to keep in sync
2. **Less Duplication**: Provider setup, modules, shared logic defined once
3. **Easy Comparison**: Can diff test vs prod by just comparing `.auto.tfvars` files
4. **Simpler Refactoring**: Changes to shared code automatically affect both environments
5. **Built-in Feature**: No need for symlinks or custom tooling
6. **State Isolation**: Each workspace has its own state, preventing cross-contamination

### Cons of Workspaces

1. **Workspace Awareness Required**: Must remember to select correct workspace
2. **Accidental Cross-Environment Operations**: Easy to forget to switch workspaces
3. **Conditional Logic Complexity**: Need `count` or `terraform.workspace` checks for environment-specific resources
4. **Less Explicit**: Not immediately obvious which environment you're working with (no separate directories)
5. **CI/CD Complexity**: Must explicitly select workspace in workflows
6. **State File Naming**: Workspace name is embedded in state path (can't easily rename)
7. **Limited Workspace Features**: Workspaces are primarily for state isolation, not full environment management

### Comparison: Workspaces vs. Multiple Directories

| Aspect | Workspaces | Multiple Directories |
|--------|-----------|---------------------|
| **Code Duplication** | Minimal (shared code) | Some (provider setup, etc.) |
| **Explicitness** | Less explicit (must check workspace) | Very explicit (directory name) |
| **Accidental Mistakes** | Higher risk (wrong workspace) | Lower risk (wrong directory) |
| **Refactoring** | Easier (change once) | Harder (change in multiple places) |
| **State Management** | Automatic (workspace in path) | Manual (separate backend configs) |
| **CI/CD** | Must select workspace | Just `cd` to directory |
| **Local Development** | Must remember workspace | Directory is self-documenting |
| **Git Diff** | Shows all changes together | Can diff per-environment easily |
| **Module Sharing** | Automatic (same codebase) | Can share via symlinks/modules |

### Recommendation

**Use workspaces if:**

- You want maximum code sharing and minimal duplication
- You're comfortable with workspace management
- You want changes to automatically propagate to both environments
- You prefer a single codebase to maintain

**Use multiple directories if:**

- You want explicit, obvious separation
- You want to prevent accidental cross-environment operations
- You prefer self-documenting structure (directory = environment)
- You want easier local development (just `cd` to the right place)
- You want to be able to easily diff environment configs in Git

Given your requirement to "diff both sides in PRs", **workspaces might actually be better** because:

- All changes show up in one PR (easier to review)
- You can see exactly what differs between test and prod in the `.auto.tfvars` files
- Shared code changes are immediately visible for both environments

### Deployment Workflow

The deployment workflow is implemented in `.github/workflows/nodes-plan-apply.yaml` and uses composite actions for modularity.

#### Workflow Triggers

- **Push to `main`**: Automatically deploys to test environment (pushes test tag and applies)
- **Push to `test` tag**: Redeploys test environment (no tag push needed)
- **Push to `prod` tag**: Redeploys prod environment (no tag push needed)
- **Manual workflow dispatch**: Allows selecting target environment (test or prod) with optional apply

#### Tag Management

Tags are automatically pushed by the `configure-deployment` action when deploying to an environment:

- **Test tag**: Pushed when deploying to test (unless already on test tag)
- **Prod tag**: Pushed when deploying to prod (unless already on prod tag)
- Tags are force-updated to point to the current commit being deployed
- Tag pushing happens before Terraform operations, ensuring tags always reflect what's deployed

#### Deployment Logic

The `configure-deployment` action determines:

- Whether to push tags based on the deployment target
- Whether to apply to test environment (`test_apply`)
- Whether to apply to prod environment (`prod_apply`)

**Deployment scenarios:**

- Push to main → Push test tag, deploy test
- Push to test tag → Deploy test (no tag push)
- Push to prod tag → Deploy prod (no tag push)
- Manual: target test → Push test tag (if not on test tag), deploy test
- Manual: target prod → Push prod tag (if on test tag or main), deploy prod

#### Terraform Operations

The `terraform-plan-apply` composite action handles:

- Workspace selection/creation (get-or-create pattern)
- Terraform plan with `-detailed-exitcode` flag (exits 0=no changes, 1=error, 2=changes)
- Logging notices for plan results (no changes vs changes detected)
- Conditional apply based on input flag
- All operations use `working-directory` instead of `cd` commands

**Questions:**

- **Q3**: Should production deployment require explicit approval (GitHub environment protection rules)?

A: No.

- **Q4**: Should we validate that the test tag exists before allowing prod deployment?

A: No

- **Q5**: Should we prevent prod deployment if the test tag is "too old" (e.g., > 7 days)?

A: No

### Terraform State Management

With workspaces, each environment automatically gets its own isolated state file:

- **Test workspace**: `gs://custodes-tf-state/terraform/tiles/nodes/test/default.tfstate`
- **Production workspace**: `gs://custodes-tf-state/terraform/tiles/nodes/prod/default.tfstate`

**How it works:**

- The backend prefix is `terraform/tiles/nodes` (configured in `versions.tf`)
- Terraform automatically appends the workspace name: `terraform/tiles/nodes/{workspace}/`
- Each workspace has its own `default.tfstate` file
- State files are created automatically on first `terraform apply`
- No manual GCS bucket setup needed beyond the base bucket and prefix

**State Locking:**

- Each workspace has its own state lock
- You can run operations on different workspaces simultaneously without conflicts
- Locks are workspace-specific, so test and prod can be managed independently

### Configuration Differences

Most differences between test and production should be captured in `.tfvars` files:

**Shared (`terraform.tfvars`)**:

```hcl
onepassword_vault_name = "tiles-secrets"
proxmox_storage_iso    = "local"
talos_version          = "1.11.5"
project_id             = "symm-custodes"
gcp_region             = "us-east1"
```

**Test-specific (`test.tfvars`)**:

```hcl
cluster_name        = "tiles-test"
external_ip_cidr    = "10.0.193.0/24"
pod_cidr            = "10.0.208.0/20"
service_cidr        = "10.0.200.0/21"
control_plane_vip   = "10.0.192.10"
start_vms           = true
apply_configs       = true
run_bootstrap        = true
```

**Production-specific (`prod.tfvars`)**:

```hcl
cluster_name        = "tiles"
external_ip_cidr    = "10.0.129.0/24"
pod_cidr            = "10.0.144.0/20"
service_cidr        = "10.0.136.0/21"
control_plane_vip   = "10.0.128.10"
start_vms           = false  # More conservative
apply_configs       = true
run_bootstrap        = false  # Manual bootstrap for prod
```

**VM configurations** should be defined in separate files or as variables:

- `test-vms.tf` or `vms.tf` with environment-specific locals
- Or as variables passed via `.tfvars`

**Questions:**

- **Q7**: Should VM configurations (node specs, IPs, etc.) be in separate `.tf` files (`test-vms.tf`, `prod-vms.tf`) or as data structures in `.tfvars`?

tfvars.

- **Q8**: Should we extract shared Talos schematic configuration to a shared location?

I don't understand but with workspaces the code is shared and the config may intentionally
differ if I'm testing a change to the schematic we use.

### Tag Management

**Tag Naming**:

- `test`: Points to the latest commit deployed to test
- `prod`: Points to the commit deployed to production

**Tag Behavior**:

- Tags are force-updated (`git tag -f`) to avoid tag conflicts
- Tags are pushed with `git push -f origin <tag>` to update remote
- The workflow has `contents: write` permission to create/update tags
- Tags are pushed automatically when deploying to an environment
- Tags are only pushed if not already on that tag (prevents unnecessary pushes)

**Current Implementation**:

- Tags are currently lightweight tags
- **TODO (Q9)**: Update to annotated tags with message including GitHub actor and current ref

### Shared Resources

Some resources are shared between environments and should remain in bootstrap or a shared module:

- **Bootstrap**: Service accounts, GitHub repo setup, 1Password vault setup
- **Talos ISOs**: Currently downloaded per-node; should this be shared or environment-specific?
- **Talos Schematic**: Currently shared; should remain shared

**Questions:**

- **Q11**: Should Talos ISO downloads be environment-specific or shared? (Currently they're per-node, but could be per-environment)

I don't want to store multiple copies of an iso just for isolation. Right now they will share them by name
but might fight over the id assigned to them. I don't really want to add a whole other "shared" chunk of terraorm though.

- **Q12**: Are there any other resources that should remain shared vs. environment-specific?

I don't want to.

### Pull Request Workflow

PRs automatically run Terraform plan for both environments:

- The workflow runs on `pull_request` events
- Both test and prod workspaces are planned
- Plan outputs are attached to PR comments via the `attach-outputs` action
- Changes to shared code (modules, bootstrap) affect both environments
- Changes to environment-specific configs show in their respective `.auto.tfvars` files
- Reviewers can see what will change in both test and prod

### Migration Status

✅ **Completed**:

- Workspace-based structure implemented
- Terraform state migrated manually
- GitHub Actions workflow updated with composite actions
- Tag-based deployment workflow implemented
- Test environment deployed via workflow
- Production environment ready for first deployment from tag

## Suggested Refinements

### 1. Environment Protection Rules

Use GitHub Environments to add approval gates for production:

- `test` environment: Auto-approve
- `prod` environment: Require manual approval

A: There's just me, I don't need to approve myself.

### 2. Deployment Status Tracking

Track which commit is deployed where:

- Add a deployment status file or use GitHub Deployments API
- Show deployment status in PR comments

**Status**: Filed as issue for future implementation

### 3. Automated Promotion

Consider a "promote to prod" button in PR comments after test deployment succeeds:

- One-click promotion workflow
- Still requires explicit action (not automatic)

A: Meh, maybe.

### 4. Configuration Validation

Add validation to ensure:

- Test and prod configs are structurally similar
- Required variables are set for each environment
- No obvious misconfigurations (e.g., prod using test IP ranges)

### 5. Rollback Strategy

Define how to rollback:

- Re-tag `test` or `prod` to a previous commit
- Re-run deployment workflow
- Document rollback procedure

A: That's the procedure, right?

### 6. Tag History

Consider keeping tag history:

- Instead of force-updating, use `test-<timestamp>` tags
- `test` and `prod` tags point to latest
- Allows auditing what was deployed when

**Status**: Force-updating tags is acceptable for now. Tag history may be considered in the future.

## Alternatives Considered

### Alternative 1: Branch-Based Strategy

- `main` → test environment
- `production` branch → prod environment
- **Rejected**: Tags are more explicit about what's deployed where

### Alternative 2: Single Workspace with Conditional Logic

- Use `count` or `for_each` based on a variable
- **Rejected**: Less clear separation, harder to diff configs

### Alternative 3: Separate Repositories

- `tiles-test` and `tiles-prod` repos
- **Rejected**: Harder to keep in sync, can't diff in PRs

## Implementation Summary

### Resolved Decisions

1. ✅ **Directory structure**: Workspaces (single `tf/nodes` directory with workspace-based isolation)
2. ✅ **Provider setup**: Shared (same file for all workspaces)
3. ✅ **Production approval**: No approval required
4. ✅ **Test tag validation**: No validation required
5. ✅ **State management**: Workspaces with automatic state path isolation
6. ✅ **VM configs**: In `.tfvars` files
7. ✅ **Talos schematic**: Shared code, config may differ per workspace
8. ✅ **Tag protection**: Force-push is acceptable
9. ✅ **Talos ISOs**: Shared by name (may fight over ID assignment)
10. ✅ **Other shared resources**: No additional shared resources desired
11. ✅ **PR planning**: Plan both environments
12. ✅ **PR diff comments**: No separate diff comment needed
13. ✅ **Migration strategy**: Test first, then prod from tag
14. ✅ **State migration**: Completed manually
15. ✅ **Tag history**: Force-update acceptable for now

### Pending Items

1. **Tag annotations (Q9)**: Currently using lightweight tags; should update to annotated tags with message including GitHub actor and current ref
2. **Deployment status tracking**: Filed as issue for future implementation

## Current Implementation

The environment strategy is implemented and operational:

- ✅ Workspace-based Terraform structure
- ✅ Tag-based deployment workflow
- ✅ Automated tag pushing on deployment
- ✅ Composite actions for modularity
- ✅ Both test and prod environments managed
- ✅ PR planning for both environments
- ✅ Terraform plan with detailed exit codes

### Code Changes Needed

1. **Tag annotations**: Update `configure-deployment` action to create annotated tags with message including GitHub actor and current ref (per Q9 answer)
