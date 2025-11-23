# Configuration Propagation Mechanism

This document describes how configuration values flow from Terraform through 1Password to the bootstrap process and into individual Helm charts via the ArgoCD app-of-apps pattern.

## Underlying challenge

We have to somehow pass values created by terraform (service account secrets, for example) as well as environment-specific static values (what DNS domain to use) into the charts, and ideally though a clear and central mechanism. We also have to handle the fact that most values.yaml strings are not template-expanded, so you need to (for example) set argo-cd.global.domain to the expanded value of "argocd.{{ .Values.cluster_name }}.symmatree.com" , which is what we use the valuesObject in application.yaml for.

## Overview

The configuration propagation mechanism allows environment-specific and runtime values (originating from Terraform) to be injected into Kubernetes applications with a single operation. Instead of managing values separately for each application, all values are collected into a union set and passed once to the `argocd-applications` chart, which then propagates them to individual applications through templated `valuesObject` blocks.

The key design decision is using 1Password as the interface between Terraform and Kubernetes: Terraform collects configuration values and stores them in a 1Password secure note (`misc-config`), and the bootstrap process retrieves them from there. This provides better isolation between infrastructure and application layers.

## Architecture

The architecture uses 1Password as the interface between Terraform (infrastructure) and Kubernetes (applications):

```
┌─────────────────────────────────────┐
│ Infrastructure Layer (Terraform)    │
│  - Collects values from variables   │
│  - Writes to 1Password misc-config  │
└──────────────┬──────────────────────┘
               │
               ↓ (writes config)
        ┌──────────────┐
        │  1Password   │ ← Interface between layers
        │ misc-config  │   (human-readable, reviewable)
        └──────┬───────┘
               │
               ↓ (retrieves config)
┌─────────────────────────────────────┐
│ Application Layer (Kubernetes)      │
│  - GitHub Actions workflow          │
│    • Loads from 1Password           │
│    • Exports as environment vars    │
│  - bootstrap.sh                     │
│    • Validates and converts to Helm │
│  - argocd-applications Chart        │
│    • valuesObject (union of values) │
│    • templates/ (symlinked)         │
│      ├── argocd-application.yaml    │
│      ├── cilium-application.yaml    │
│      ├── cilium-config-application  │
│      └── cert-manager-application   │
│  - Individual Charts                │
│    • Receive via valuesObject       │
└─────────────────────────────────────┘
```

**Key Design Points:**
- **1Password as Interface**: Complete separation between infrastructure and application layers
- **Single Source of Truth**: Terraform writes, Kubernetes reads - no direct coupling
- **Human-Friendly**: Configuration can be reviewed in 1Password UI without running Terraform
- **No Environment Variables**: Terraform doesn't require many env vars; values come from its own variables

## Bootstrap Process

### 1. Terraform → 1Password Storage

Terraform collects cluster configuration values from its variables and outputs, then stores them in a 1Password secure note item named `{cluster_name}-misc-config`. The item contains a `config` section with the following fields:

- `targetRevision` - Git branch/tag to deploy
- `cluster_name` - Name of the Kubernetes cluster
- `pod_cidr` - CIDR range for pod IPs
- `external_ip_cidr` - CIDR range for external IPs

**Note:** `vault_name` is the 1Password vault name itself (currently `tiles-secrets`) and is hardcoded in the workflow. `project_id` is currently stored as a GitHub secret but can be migrated to misc-config in the future.

**Benefits of this approach:**
- **No environment variables required**: Humans can run `terraform plan` or `terraform apply` without providing a large number of environment variables - Terraform reads from its own variables and writes to 1Password
- **Easy review**: The current configuration can be easily reviewed in 1Password's UI
- **Clear interface**: 1Password serves as the complete interface between Terraform (infrastructure) and Kubernetes (applications), providing better isolation and separation of concerns

### 2. GitHub Actions Workflow

The `bootstrap-cluster` workflow (`.github/workflows/bootstrap-cluster.yaml`) performs the following steps:

1. **Loads sensitive secrets from 1Password** - Retrieves kubeconfig, GCP service account credentials, and VPN config
2. **Loads cluster config from 1Password** - Uses the `1password/load-secrets-action` with `export-env: true` to retrieve all fields from the `{cluster_name}-misc-config` item's `config` section (which was previously written by Terraform) and export them directly as environment variables:
   - Values from misc-config (targetRevision, pod_cidr, cluster_name, external_ip_cidr)
   - `vault_name` (hardcoded to "tiles-secrets")
   - `project_id` (from GitHub secret `PROJECT_ID`, can be migrated to misc-config)
3. **Calls bootstrap.sh** - The script reads environment variables, validates they are set, and converts them to Helm `--set` arguments

### 3. Bootstrap Script

The `bootstrap.sh` script (`charts/bootstrap.sh`) defines a `required_vars` array containing all configuration values that must be provided:

```bash
required_vars=(
	"targetRevision"
	"pod_cidr"
	"cluster_name"
	"external_ip_cidr"
	"vault_name"
	"project_id"
)
```

For each variable, the script:
1. Validates it is set (exits with error if missing)
2. Adds it to `helm_args` as `--set var=value`

The script then installs:
1. **Cilium** - CNI with values passed via `--set` arguments
2. **ArgoCD** - GitOps controller with cluster-specific domain configuration
3. **argocd-applications** - The app-of-apps that manages all other applications

### 4. ArgoCD App-of-Apps Pattern

The `argocd-applications` chart (`charts/argocd-applications/`) serves as the root application that manages all other applications. It uses the ArgoCD app-of-apps pattern where:

- **Main Application** (`application.yaml`) - Defines the `argocd-applications` application itself
- **Templates Directory** (`templates/`) - Contains symlinked `application.yaml` files from individual charts

#### Main Application Configuration

The `argocd-applications/application.yaml` file includes a `valuesObject` block that contains the union of all values needed by any downstream application:

```yaml
valuesObject:
  # Propagate to other application.yaml files
  targetRevision: "{{ .Values.targetRevision }}"
  pod_cidr: "{{ .Values.pod_cidr }}"
  cluster_name: "{{ .Values.cluster_name }}"
  external_ip_cidr: "{{ .Values.external_ip_cidr }}"
  vault_name: "{{ .Values.vault_name }}"
  project_id: "{{ .Values.project_id }}"
```

These values are templated using Helm's `{{ .Values.* }}` syntax, allowing them to be passed from the bootstrap process.

#### Template Files

The `templates/` directory contains symlinked `application.yaml` files from individual charts:

- `argocd-application.yaml` (symlinked from `charts/argocd/application.yaml`)
- `cilium-application.yaml` (symlinked from `charts/cilium/application.yaml`)
- `cilium-config-application.yaml` (symlinked from `charts/cilium-config/application.yaml`)
- `cert-manager-application.yaml` (symlinked from `charts/cert-manager/application.yaml`)

Each template file defines an ArgoCD Application resource that references its corresponding chart. The key mechanism is that these templates can reference values from the parent `argocd-applications` chart's `valuesObject`:

```yaml
# Example from cert-manager-application.yaml
valuesObject:
  cluster_name: "{{ .Values.cluster_name }}"
  project_id: "{{ .Values.project_id }}"
  vault_name: "{{ .Values.vault_name }}"
```

When ArgoCD renders these templates, the `{{ .Values.* }}` references resolve to values from the `argocd-applications` chart's `valuesObject`, which were originally passed from Terraform via `bootstrap.sh`.

#### Template Expansion Pattern

**Important**: Helm's `values.yaml` files do **not** expand template expressions. If you need to construct values from other values (like domain names), you must use the `valuesObject` block in the Application's `application.yaml` file.

For example, to set `argo-cd.global.domain` to `"argocd.{{ .Values.cluster_name }}.symmatree.com"`, you cannot do this in `values.yaml` because templates aren't expanded there. Instead, you must do the expansion in the Application's `valuesObject`:

```yaml
# In argocd/application.yaml
valuesObject:
  argo-cd:
    global:
      domain: "argocd.{{ .Values.cluster_name }}.symmatree.com"  # ✅ Expanded by ArgoCD
```

This works because ArgoCD renders the Application resource (including the `valuesObject` block) as a Helm template, so `{{ .Values.* }}` expressions are evaluated at that level.

**Rule of thumb**:
- Use `values.yaml` for static placeholder values
- Use `valuesObject` in `application.yaml` for:
  - Passing values through to child charts
  - Template expansion (constructing values from other values)
  - Dynamic values that need to be computed

## Value Propagation Flow

1. **Terraform** → Collects configuration values from variables and outputs, then stores them in 1Password `{cluster_name}-misc-config` item (config section)
2. **1Password** → Serves as the interface between Terraform and Kubernetes, storing the current configuration state
3. **GitHub Actions Workflow** → Retrieves misc-config fields from 1Password using `1password/load-secrets-action` with `export-env: true`, which automatically exports them as environment variables
4. **bootstrap.sh** → Reads environment variables, validates they are set, and converts to Helm `--set` arguments
5. **Helm install** → Passes values to `argocd-applications` chart via `--set` flags
6. **argocd-applications/values.yaml** → Contains placeholder values used for:
   - **Helm requirement**: Helm 4.0.0+ requires at least an empty `values.yaml` file
   - **Documentation**: Documents the expected value structure
   - **Rendered YAML generation**: Used by `build.sh` to generate `rendered.yaml` files via `helm template` for debugging and PR review
   - **Template validation**: Helps confirm values are used properly in templates, especially for complex Helm logic
7. **argocd-applications/application.yaml** → `valuesObject` block receives actual values from Helm `--set` arguments
8. **Template files** → Reference `{{ .Values.* }}` which resolve to parent chart's values
9. **Individual charts** → Receive values via their Application's `valuesObject` blocks

## Benefits

1. **Single Point of Configuration** - All environment-specific values are passed once to `argocd-applications`
2. **Automatic Propagation** - Values automatically flow to individual charts through templated `valuesObject` blocks
3. **Type Safety** - Helm validates that all referenced values exist
4. **Maintainability** - Adding a new value requires:
   - Adding it to `required_vars` in `bootstrap.sh`
   - Adding it to `argocd-applications/values.yaml` (with placeholder)
   - Adding it to `argocd-applications/application.yaml` `valuesObject`
   - Using it in individual chart templates as needed
5. **Separation of Concerns** - Terraform manages infrastructure values, Helm manages application deployment
6. **Debugging & Review** - `values.yaml` files enable generation of `rendered.yaml` files via `helm template`, making it easier to:
   - Debug template rendering issues
   - Review generated manifests in PRs
   - Validate complex Helm logic beyond simple interpolation
   - For third-party charts (ArgoCD, Cilium), review the complex resulting manifests even without final runtime values

## Adding New Values

To add a new configuration value that needs to propagate to charts:

1. **Update Terraform** - Add the field to the `misc_config` item's `config` section in `tf/modules/talos-cluster/main.tf`. This ensures Terraform will collect the value and write it to 1Password when applied.
2. **Update GitHub Actions Workflow** - Add the field to the "Load cluster config from 1Password" step's `env` block:
   ```yaml
   - name: Load cluster config from 1Password
     uses: 1password/load-secrets-action@v3
     with:
       export-env: true
     env:
       # ... existing values ...
       new_value: "op://tiles-secrets/${{ github.event.inputs.cluster }}-misc-config/config/new_value"
   ```
   The `export-env: true` flag automatically exports all values in the `env` block as environment variables.
3. **Update `bootstrap.sh`** - Add the variable name to `required_vars` array
4. **Update `argocd-applications/values.yaml`** - Add placeholder value (used for `rendered.yaml` generation and documentation)
5. **Update `argocd-applications/application.yaml`** - Add to `valuesObject` block: `varName: "{{ .Values.varName }}"`
6. **Update individual chart templates** - Reference the value in their `valuesObject` blocks as needed
7. **Regenerate rendered.yaml** - Run `build.sh` to regenerate `rendered.yaml` files for review

## Example: Adding a New Value

Suppose we want to add a `region` value that needs to be passed to the `cert-manager` chart:

1. **Terraform** (`tf/modules/talos-cluster/main.tf`):
   ```hcl
   resource "onepassword_item" "misc_config" {
     # ... existing config ...
     section {
       label = "config"
       field {
         label = "region"
         value = var.region  # or hardcoded value
       }
       # ... other fields ...
     }
   }
   ```

2. **GitHub Actions Workflow** (`.github/workflows/bootstrap-cluster.yaml`):
   ```yaml
   - name: Load cluster config from 1Password
     uses: 1password/load-secrets-action@v3
     with:
       export-env: true
     env:
       # ... existing values ...
       region: "op://tiles-secrets/${{ github.event.inputs.cluster }}-misc-config/config/region"
   ```
   The `export-env: true` flag automatically exports all values in the `env` block as environment variables, so no separate export step is needed.

3. **bootstrap.sh**:
   ```bash
   required_vars=(
       # ... existing vars ...
       "region"
   )
   ```

4. **argocd-applications/values.yaml**:
   ```yaml
   # ... existing values ...
   region: "placeholder-region"
   ```
   This placeholder value is used when generating `rendered.yaml` via `helm template` for debugging and PR review.

5. **argocd-applications/application.yaml**:
   ```yaml
   valuesObject:
       # ... existing values ...
       region: "{{ .Values.region }}"
   ```

6. **templates/cert-manager-application.yaml**:
   ```yaml
   valuesObject:
       # ... existing values ...
       region: "{{ .Values.region }}"
   ```

The value will now flow from Terraform (collects and writes) → 1Password (stores) → GitHub Actions (retrieves) → bootstrap.sh → argocd-applications → cert-manager chart.

## Rendered YAML Generation

The `values.yaml` files serve an important purpose beyond just documentation: they enable generation of `rendered.yaml` files for debugging and PR review.

### How It Works

The `build.sh` script runs `helm template` for each chart using the placeholder values from `values.yaml`:

```bash
helm template "${name}" . --namespace "${name}" \
    --skip-crds \
    --set "targetRevision=$targetRevision" \
    --set "cluster_name=$cluster_name" \
    --set "pod_cidr=$pod_cidr" \
    --set "vault_name=$vault_name" \
    >rendered.yaml
```

### Why This Matters

1. **Third-Party Charts** (ArgoCD, Cilium): The resulting manifests are complex. Having `rendered.yaml` allows reviewing the full generated YAML even without final runtime values, which is vital for understanding what will be deployed.

2. **Custom Charts**: While simpler, `rendered.yaml` still helps:
   - Confirm values are used properly in templates
   - Validate complex Helm logic beyond simple interpolation
   - Review template rendering during development

3. **PR Review**: Reviewers can see the actual generated manifests, making it easier to spot issues and understand the impact of changes.

4. **Helm Requirement**: Helm 4.0.0+ requires at least an empty `values.yaml` file, so this practice also satisfies that requirement.

## Handling Different Value Types

The configuration mechanism handles three types of values differently:

### 1. Non-Sensitive Configuration (misc-config)

**Source**: Terraform variables and outputs
**Storage**: 1Password `{cluster_name}-misc-config` item (config section)
**Propagation**: Via bootstrap.sh → argocd-applications → individual charts
**Examples**: `cluster_name`, `pod_cidr`, `external_ip_cidr`, `targetRevision`

These values flow through the standard propagation mechanism described above.

### 2. Service Account Secrets

**Source**: Terraform-created service accounts (e.g., GCP service accounts)
**Storage**: 1Password items (e.g., `{cluster_name}-cert-manager-dns01-sa-key`)
**Propagation**: Directly via OnePasswordItem CRD in charts
**Example**: cert-manager DNS01 solver service account key

Service account secrets are **not** passed through the bootstrap flow. Instead, charts use the OnePassword operator's `OnePasswordItem` CRD to pull secrets directly from 1Password:

```yaml
# In cert-manager/templates/clouddns-sa-secret.yaml
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: cert-manager-dns01-sa-key
spec:
  itemPath: vaults/{{ .Values.vault_name }}/items/{{ .Values.cluster_name }}-cert-manager-dns01-sa-key
```

This approach:
- Keeps secrets out of the bootstrap flow
- Allows charts to manage their own secret lifecycle
- Works with ArgoCD's sync process (OnePassword operator handles the sync)

### 3. Environment-Specific Static Values

**Source**: Environment configuration (not from Terraform)
**Storage**: 1Password misc-config or GitHub secrets
**Propagation**: Via bootstrap.sh → argocd-applications
**Examples**: `vault_name`, `project_id` (currently GitHub secret, can migrate to misc-config)

These are typically hardcoded per-environment or stored separately from Terraform-managed values.

## Design Decisions

### Why 1Password as the Interface?

The use of 1Password as the interface between Terraform and Kubernetes provides several key benefits:

- **Separation of Concerns**: Complete isolation between infrastructure (Terraform) and application (Kubernetes) layers, with 1Password as the well-defined interface
- **No Environment Variable Burden**: Humans can run `terraform plan` or `terraform apply` without needing to provide many environment variables - Terraform reads from its own variables and writes to 1Password
- **Easy Review**: The current configuration can be easily reviewed in 1Password's UI, making it simple to see what values are currently stored
- **Single Source of Truth**: Terraform manages infrastructure and writes config values to 1Password, ensuring consistency
- **Security**: Sensitive values can be stored securely, non-sensitive values in misc-config
- **Version Control**: Config values are managed by Terraform, not committed to git
- **Workflow Integration**: GitHub Actions can easily load values using the 1Password action

### Why valuesObject for Template Expansion?

Helm's `values.yaml` files are static YAML and do not support template expansion. When you need to construct values from other values (like `"argocd.{{ .Values.cluster_name }}.symmatree.com"`), you must use the `valuesObject` block in the Application resource because:

1. **ArgoCD renders Applications as templates**: The Application resource itself is templated by ArgoCD, so `{{ .Values.* }}` expressions in `valuesObject` are evaluated
2. **Values are passed to charts**: The expanded values in `valuesObject` are then passed to the chart's Helm rendering, where they can be used normally
3. **Single expansion point**: All template expansion happens at the Application level, keeping charts simpler

This pattern allows you to:
- Build domain names from cluster names
- Construct paths from multiple values
- Create any dynamic configuration that depends on other values

### Why Separate Secrets from Config?

Service account secrets and other sensitive values are handled separately from configuration values because:

1. **Different lifecycle**: Secrets are created by Terraform but managed by Kubernetes (via OnePasswordItem CRD)
2. **Security**: Secrets don't flow through the bootstrap process, reducing exposure
3. **Flexibility**: Charts can pull secrets on-demand via the OnePassword operator
4. **ArgoCD compatibility**: OnePasswordItem resources sync naturally with ArgoCD's reconciliation

## Potential Improvements

While the current mechanism works well, here are some potential enhancements to consider:

### 1. Standardize 1Password Item Naming

Currently, items follow patterns like `{cluster_name}-misc-config` and `{cluster_name}-cert-manager-dns01-sa-key`. Consider:
- Documenting a naming convention: `{cluster_name}-{category}-{purpose}`
- Creating a helper script to validate item names match conventions
- Adding Terraform validation to ensure items follow the pattern

### 2. Value Categorization Documentation

Create explicit categories in documentation:
- **Infrastructure-derived**: Values computed by Terraform (pod_cidr, external_ip_cidr)
- **Environment config**: Static per-environment values (cluster_name, targetRevision)
- **Secrets**: Handled via OnePasswordItem CRD
- **Computed**: Values that need template expansion (domain names)

### 3. Template Expansion Helper

Consider creating a small script or documentation template for common expansion patterns:
```yaml
# Common patterns:
domain: "{{ .Values.service_name }}.{{ .Values.cluster_name }}.{{ .Values.base_domain }}"
path: "{{ .Values.base_path }}/{{ .Values.cluster_name }}"
```

### 4. Validation Script

Add a validation script that:
- Checks all required values are in `required_vars`
- Validates values are in `argocd-applications/values.yaml`
- Ensures values are in `argocd-applications/application.yaml` valuesObject
- Verifies 1Password item structure matches expected fields

### 5. Better Documentation of valuesObject Patterns

Document common patterns:
- **Pass-through**: `value: "{{ .Values.value }}"` - just pass the value through
- **Template expansion**: `domain: "{{ .Values.service }}.{{ .Values.cluster }}.domain.com"` - construct from multiple values
- **Nested structures**: How to pass nested Helm values (like `argo-cd.global.domain`)

### 6. Consider Migrating project_id to misc-config

Currently `project_id` is a GitHub secret. Consider:
- Adding it to Terraform's misc_config
- Updating the workflow to load it from 1Password
- Removing the GitHub secret dependency

This would make all non-secret config flow through the same mechanism.

### Why Environment Variables?

- **Simplicity**: `bootstrap.sh` reads from environment, no need for a separate config file
- **Standard Practice**: Common pattern for passing config to scripts
- **Validation**: `bootstrap.sh` validates all required variables are set before proceeding

### Future Migration Path

Currently, `project_id` is stored as a GitHub secret. It can be migrated to misc-config by:
1. Adding `project_id` field to Terraform's `misc_config` resource
2. Updating the workflow to load it from 1Password instead of GitHub secrets
3. Removing the GitHub secret reference
