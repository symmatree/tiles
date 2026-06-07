# Environment Strategy: Test and Production Parallel Environments

## Overview

This document describes the strategy for managing two parallel Terraform environments (test and production) with a tag-based deployment workflow, while maintaining side-by-side configuration files for easy comparison and review in pull requests.

## Procedures

### Making Changes and Deploying

**For Terraform or Helm/Kubernetes changes:**

1. **Create a Pull Request** to `main` branch
   - Make your changes to Terraform files (`tf/nodes/`) or Helm charts
   - The PR will automatically run Terraform plan for both test and prod environments
   - Review the plan outputs attached to the PR

2. **Merge to `main`**
   - Upon merge, the workflow automatically:
     - Updates the **`test`** and **`prod`** tags to point to the merged commit
     - When Terraform or non-chart files changed: deploys to **both** test and prod environments in parallel (Terraform apply)
     - When only `charts/` or `tanka/` changed: skips Terraform; ArgoCD syncs from the updated tags

3. **Manual full cluster cycle (optional)**
   - Trigger **`nodes-plan-apply`** via `workflow_dispatch`
   - Select environment(s), enable **taint**, **apply**, and **bootstrap** (or **bootstrap_profile: fresh_cluster**) as needed

4. **ArgoCD deployment**
   - Child Applications track the `test` and `prod` Git tags with automated sync enabled (`syncPolicy.automated` on each Application).
   - **Tag updates do not apply instantly.** ArgoCD reconciles on a timer and caches Git work in two layers ([Argo CD HA / performance docs](https://argo-cd.readthedocs.io/en/stable/operator-manual/high_availability/)):
     - **Revision cache** (symbolic ref such as `prod` -> commit SHA): expiration matches `timeout.reconciliation` plus `timeout.reconciliation.jitter` in `argocd-cm` (see `charts/argocd/rendered.yaml`; currently 120s + up to 60s jitter per app).
     - **Manifest cache** (commit SHA -> generated manifests, including Helm renders): `reposerver.repo.cache.expiration` in `charts/argocd/values.yaml` (set to **30m**; upstream default is **24h**, which is a poor fit for tag-based deploys and in-repo Helm).
   - After moving `test` or `prod`, expect child apps to go OutOfSync and auto-sync within a few minutes in the normal case. If nothing moves, use **Refresh** in the Argo CD UI (ordinary refresh is enough; Hard Refresh is not required) or sync the Application manually.
   - **Git webhooks** to Argo CD are the recommended way to avoid polling and cache latency at scale; not configured on these clusters yet.
   - Test cluster tracks the `test` tag; production tracks the `prod` tag.

**Workflow Summary:**

```text
PR -> main -> auto-deploy test+prod (both tags) -> Argo CD picks up tag within reconcile/cache bounds (minutes, not instant)
```

## Current State

The repository currently implements:

- Terraform workspaces (`test` and `prod`) in `tf/nodes` directory
- Test environment active (`tiles-test` cluster)
- Production environment ready (`tiles` cluster)
- Separate state files per workspace in GCS backend
- Tag-based deployment workflow (`test` and `prod` tags)
- Automatic tag pushing when deploying to environments
- Automatic deployment on push to `main` branch (deploys to **both** test and prod when Terraform-relevant; charts-only merges promote both tags without Terraform)
- Manual deployment via `workflow_dispatch` with environment selection, optional taint, apply, and bootstrap
- Composite actions for modular workflow steps
- PR planning for both test and prod environments

## Architecture

### Architecture Principles

1. **Parallel Environments**: Test and production are managed as separate Terraform workspaces
2. **Shared Bootstrap**: The bootstrap Terraform (`tf/bootstrap`) remains shared since it initializes resources for both environments
3. **Side-by-Side Configuration**: Both environment configurations live in the same source tree for easy diffing in PRs
4. **Tag-Based Deployment**: Git tags (`test` and `prod`) track what's deployed; Argo CD child Applications follow those tags with automated sync, subject to reconcile interval and repo-server cache TTL (see procedures above)
5. **Promotion Workflow**: Production deployments can be promoted from test-tagged commits or deployed directly
6. **Shared Code, Different Variables**: Most differences between environments are represented as different `.tfvars` files

### Directory Structure

**Current Implementation (Workspaces):**

```text
tf/
├── bootstrap/          # Shared bootstrap
│   └── ...
└── nodes/              # Single directory with workspaces
    ├── main.tf                   # Shared provider setup
    ├── cluster.tf                # Cluster module (shared, uses variables)
    ├── terraform.tfvars          # Shared defaults
    ├── test.tfvars                # Test-specific (explicitly loaded for test workspace)
    ├── prod.tfvars                # Prod-specific (explicitly loaded for prod workspace)
    ├── variables.tf
    ├── outputs.tf
    ├── versions.tf
    └── ... (other shared files)
```

**Structure Decision:**

- **A1**: Using Terraform workspaces (single `tf/nodes` directory with workspace-based isolation)
- **A2**: Shared `main.tf` (provider setup) - same file for all workspaces

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
- **Variable Overrides**: Use `.tfvars` files that are workspace-specific (explicitly loaded via `-var-file`)

### Directory Structure with Workspaces

```text
tf/nodes/
├── main.tf                    # Providers, data sources (shared)
├── variables.tf               # Variable definitions (shared)
├── versions.tf                # Backend config (shared, workspace-aware)
├── terraform.tfvars           # Shared defaults for both environments
├── test.tfvars                # Explicitly loaded when workspace=test
├── prod.tfvars                # Explicitly loaded when workspace=prod
├── cluster.tf                 # Cluster module (shared, uses variables)
├── talos-iso.tf              # Shared Talos ISO handling
├── remote.tf                 # Remote state configuration
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

Environment-specific variables are loaded explicitly via `-var-file` flags in the workflow. The naming convention `{workspace}.tfvars` means:

- When `workspace = test`: Explicitly loads `test.tfvars` via `-var-file=test.tfvars`
- When `workspace = prod`: Explicitly loads `prod.tfvars` via `-var-file=prod.tfvars`

**Note:** Files are named `.tfvars` (not `.auto.tfvars`) to prevent Terraform from automatically loading both files, which would cause conflicts.

**Example files:**

```hcl
# terraform.tfvars (shared)
onepassword_vault_name = "tiles-secrets"
proxmox_storage_iso    = "local"
talos_version          = "1.11.5"
project_id             = "symm-custodes"
gcp_region             = "us-east1"

# test.tfvars
cluster_name        = "tiles-test"
external_ip_cidr    = "10.0.193.0/24"
pod_cidr            = "10.0.208.0/20"
service_cidr        = "10.0.200.0/21"
control_plane_vip   = "10.0.192.10"
start_vms           = true
apply_configs       = true
run_bootstrap       = true

# prod.tfvars
cluster_name        = "tiles"
external_ip_cidr    = "10.0.129.0/24"
pod_cidr            = "10.0.144.0/20"
service_cidr        = "10.0.136.0/21"
control_plane_vip   = "10.0.128.10"
start_vms           = false
apply_configs       = true
run_bootstrap       = false
```

### Resource Creation

The current implementation uses a single `cluster` module that is instantiated once per workspace. Environment-specific configuration is provided via `.tfvars` files:

```hcl
# cluster.tf (shared across workspaces)
module "cluster" {
  source = "../modules/talos-cluster"
  cluster_name = var.cluster_name  # From .tfvars
  vms = var.virtual_machines       # From .tfvars
  # ... other config from variables
}
```

Each workspace explicitly loads its corresponding `.tfvars` file via `-var-file`:

- `test` workspace → `test.tfvars` (loaded with `-var-file=test.tfvars`)
- `prod` workspace → `prod.tfvars` (loaded with `-var-file=prod.tfvars`)

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
        run: terraform plan -lock-timeout=5m -input=false -var-file=test.tfvars

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
        run: terraform plan -lock-timeout=5m -input=false -var-file=prod.tfvars

      - name: Terraform apply
        working-directory: tf/nodes
        run: terraform apply -lock-timeout=5m -auto-approve
```

**State Path Details:**

- After `terraform init`, Terraform knows about the backend
- When you select/create a workspace, Terraform will use that workspace name in the state path
- The state file path is: `gs://custodes-tf-state/terraform/tiles/nodes/{workspace}/default.tfstate`
- No manual GCS operations needed - Terraform handles everything automatically

### Why Workspaces Were Chosen

Workspaces were selected for this implementation because:

1. **Single Source of Truth**: All code in one place, easier to keep in sync
2. **Less Duplication**: Provider setup, modules, shared logic defined once
3. **Easy Comparison**: Can diff test vs prod by just comparing `.tfvars` files
4. **Simpler Refactoring**: Changes to shared code automatically affect both environments
5. **Built-in Feature**: No need for symlinks or custom tooling
6. **State Isolation**: Each workspace has its own state, preventing cross-contamination
7. **PR Review**: All changes show up in one PR, making it easy to see what differs between test and prod in the `.tfvars` files

**Trade-offs:**

- Must remember to select correct workspace (mitigated by CI/CD automation)
- Workspace name is embedded in state path (can't easily rename)
- Less explicit than separate directories (must check workspace to know which environment)

### Deployment Workflow

The deployment workflow is implemented in `.github/workflows/nodes-plan-apply.yaml` with three jobs:

1. **`resolve-matrix`** -- charts-only detection, tag promotion (single git writer), dynamic test/prod matrix
2. **`cluster`** -- parallel matrix legs (separate WireGuard clients per env): optional taint, Terraform plan/apply, optional bootstrap
3. **`pr-summary`** -- aggregates plan artifacts onto the PR

Composite actions: `configure-deployment`, `cluster-taint`, `terraform-plan-apply`, `cluster-bootstrap`, `wg-quick`.

#### Workflow Triggers

- **Push to `main`**: Promotes **both** `test` and `prod` tags; applies Terraform to both environments when non-chart files changed; skips Terraform for charts/tanka-only merges
- **Push to `test` tag**: Redeploys test environment (no tag push)
- **Push to `prod` tag**: Redeploys prod environment (no tag push)
- **Pull request**: Parallel plan for test and prod (skipped when only charts/tanka changed)
- **Schedule**: Parallel plan for test and prod
- **Manual workflow dispatch**: Selected environment(s); optional taint, apply, bootstrap (`bootstrap_profile: fresh_cluster` preset for full rebuild)

#### Automatic Tag Pushing

Tags are automatically updated by the `configure-deployment` action in the **`resolve-matrix`** job (matrix legs never push):

- **Push to `main`**: Both **`test`** and **`prod`** tags updated to the merged commit (including charts-only merges)
- **Manual apply**: Tags updated for the selected environment(s) when apply is enabled
- Tags are force-updated before Terraform operations on apply paths

#### Deployment Logic

The `configure-deployment` action determines:

- Whether to push tags based on the deployment target
- Whether to apply to test environment (`test_apply`)
- Whether to apply to prod environment (`prod_apply`)

**Deployment scenarios:**

- Push to main (Terraform changes) -> Update test and prod tags, deploy both
- Push to main (charts/tanka only) -> Update test and prod tags, skip Terraform
- Push to test tag -> Deploy test (no tag update)
- Push to prod tag -> Deploy prod (no tag update)
- Manual: environments + apply -> Update tag(s) for selected env(s), deploy selected leg(s)
- Manual: taint + apply + bootstrap -> Full cluster rebuild cycle for selected env(s)

#### Terraform Operations

The `terraform-plan-apply` composite action handles:

- Workspace selection/creation (get-or-create pattern)
- Terraform plan with `-detailed-exitcode` flag (exits 0=no changes, 1=error, 2=changes)
- Logging notices for plan results (no changes vs changes detected)
- Conditional apply based on input flag
- All operations use `working-directory` instead of `cd` commands

**Decisions:**

- **A3**: Production deployment does not require explicit approval (no GitHub environment protection rules)
- **A4**: No validation that test tag exists before allowing prod deployment
- **A5**: No age-based restrictions on prod deployment (test tag can be any age)

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

**Decisions:**

- **A7**: VM configurations are defined as data structures in `.tfvars` files (not separate `.tf` files)
- **A8**: Talos schematic configuration remains in shared code; workspace-specific overrides can be provided via variables if needed for testing schematic changes

### Tag Management

**Tag Naming**:

- `test`: Points to the latest commit deployed to test
- `prod`: Points to the commit deployed to production

**Tag Behavior**:

- Tags are force-updated (`git tag -f`) to point to the desired commit
- Tags are pushed with `git push -f origin <tag>` to update remote
- The workflow has `contents: write` permission to create/update tags
- Tags are updated automatically when deploying to an environment
- Tags are only updated if not already pointing to the current commit (prevents unnecessary updates)

**Current Implementation**:

- Tags are annotated tags with deployment metadata (GitHub actor and current ref)

### Shared Resources

Some resources are shared between environments and remain in bootstrap or as shared modules:

- **Bootstrap**: Service accounts, GitHub repo setup, 1Password vault setup
- **Talos ISOs**: Downloaded per-node, shared by name across environments (may conflict over ID assignment)
- **Talos Schematic**: Shared code; workspace-specific overrides can be provided via variables if needed

**Decisions:**

- **A11**: Talos ISO downloads are shared by name across environments (not duplicated per environment). They may conflict over ID assignment, but this is acceptable to avoid storing multiple copies.
- **A12**: No additional shared resources beyond what's already in bootstrap

### Pull Request Workflow

PRs automatically run Terraform plan for both environments:

- The workflow runs on `pull_request` events
- Both test and prod workspaces are planned
- Plan outputs are attached to PR comments via the `attach-outputs` action
- Changes to shared code (modules, bootstrap) affect both environments
- Changes to environment-specific configs show in their respective `.tfvars` files
- Reviewers can see what will change in both test and prod

## Suggested Refinements

### 1. Environment Protection Rules

**Status**: Not implemented. No approval gates needed (single operator).

### 2. Deployment Status Tracking

Track which commit is deployed where:

- Add a deployment status file or use GitHub Deployments API
- Show deployment status in PR comments

**Status**: Filed as issue for future implementation

### 3. Automated Promotion

Consider a "promote to prod" button in PR comments after test deployment succeeds:

- One-click promotion workflow
- Still requires explicit action (not automatic)

**Status**: Not implemented. May be considered in the future.

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

**Status**: Rollback procedure is to re-tag `test` or `prod` to a previous commit and re-run the deployment workflow.

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
13. ✅ **Tag history**: Force-update acceptable for now

### Pending Items

1. **Deployment status tracking**: Filed as issue for future implementation

## Current Implementation

The environment strategy is implemented and operational:

- ✅ Workspace-based Terraform structure
- ✅ Tag-based deployment workflow
- ✅ Automated tag pushing on deployment
- ✅ Composite actions for modularity
- ✅ Both test and prod environments managed
- ✅ PR planning for both environments
- ✅ Terraform plan with detailed exit codes
- ✅ Annotated tags with deployment metadata
