# Configuration Propagation Mechanism

How configuration values flow from Terraform into individual Helm charts, via the Argo CD app-of-apps pattern.

## Underlying challenge

We have to somehow pass values created by terraform (service account secrets, for example) as well as environment-specific static values (what DNS domain to use) into the charts, and ideally though a clear and central mechanism. We also have to handle the fact that most values.yaml strings are not template-expanded, so you need to (for example) set argo-cd.global.domain to the expanded value of "argocd.{{ .Values.cluster_name }}.symmatree.com" , which is what we use the valuesObject in application.yaml for.

## Overview

The configuration propagation mechanism allows environment-specific and runtime values (originating from Terraform) to be injected into Kubernetes applications with a single operation. Instead of managing values separately for each application, all values are collected into a union set and passed once to the `argocd-applications` chart, which then propagates them to individual applications through templated `valuesObject` blocks.

Terraform passes the set directly into the Helm releases it installs. Nearly every value is a `tf/nodes` variable, so there is nothing to stage anywhere: the values live in `test.tfvars` and `prod.tfvars` and reach the cluster in the same apply that creates it.

## Architecture

Values go from Terraform into the installer chart, and from there down the Application tree:

```
tf/nodes variables (test.tfvars / prod.tfvars)
        │
        ↓  module.cluster.app_of_apps_values
┌───────────────────────────────────────────┐
│ Terraform (tf/nodes/k8s-argocd.tf)        │
│   helm_release argocd-applications-installer│
└───────────────────┬───────────────────────┘
                    │  Application.spec.source.helm.valuesObject
                    ↓
┌───────────────────────────────────────────┐
│ charts/argocd-applications                │
│   one child Application per component,    │
│   each with its own valuesObject          │
└───────────────────┬───────────────────────┘
                    ↓
        each component's own chart
```

**Key Design Points:**
- **1Password as Interface**: Complete separation between infrastructure and application layers
- **Single Source of Truth**: Terraform writes, Kubernetes reads - no direct coupling
- **Human-Friendly**: Configuration can be reviewed in 1Password UI without running Terraform
- **No Environment Variables**: Terraform doesn't require many env vars; values come from its own variables

## Bootstrap Process

### 1. Where the values come from

`module.cluster.app_of_apps_values` is the propagated set. Nearly all of it is
`tf/nodes` variables, set per cluster in `test.tfvars` and `prod.tfvars`;
`project_id` comes from the `tf/bootstrap` remote state, and `targetRevision` is
derived from the cluster name.

### 2. Terraform installs what Argo CD needs before it can take over

Argo CD cannot install itself, its own CRDs, or the CNI its pods need in order
to schedule. Terraform installs exactly that set and then hands over: the last
thing it applies is the `argocd-applications` Application, and everything after
that is Argo CD's. See [`tf/nodes/README.md`](../tf/nodes/README.md) for what is
in that set and why each piece is there.

Ordering is the Terraform dependency graph. Nothing waits on Argo CD's
controllers before the Application is applied -- an Application is a custom
resource, so Argo CD reconciles it whenever the controller starts.

Both Helm releases set `wait = false`, and have to: Argo CD's oauth2-proxy
cannot become ready until the 1Password operator exists, and Argo CD is what
deploys it. A readiness gate there deadlocks.

**Stuck root sync:** re-applying does not repair an existing `SyncError` on
`argocd-applications`; refresh or sync that Application by hand. See
[`charts/argocd-applications/README.md`](../charts/argocd-applications/README.md).

### 3. How values reach the charts

`module.cluster.app_of_apps_values` holds the propagated set. Terraform
`yamlencode`s it into the installer release, whose Application carries it in
`valuesObject` to `charts/argocd-applications`, whose child Applications carry
the subset each component needs into that component's chart.

Cilium and Argo CD are installed from their own charts with the same value files
their Applications use, plus the keys Argo CD would template into `valuesObject`
-- so Terraform and Argo CD render identical output from identical inputs, which
is what lets Terraform adopt an install Argo CD was managing.

`scripts/helm-common.bash` reads the propagated key names from
`charts/argocd-applications-installer/values.yaml` so `build.sh` can render every
chart offline with a placeholder for each.

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

When ArgoCD renders these templates, the `{{ .Values.* }}` references resolve to values from the `argocd-applications` chart's `valuesObject`, which Terraform supplies directly from `module.cluster.app_of_apps_values`.

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

1. **Terraform** → collects the set as `module.cluster.app_of_apps_values`, nearly all of it `tf/nodes` variables
2. **Terraform** → passes it into the installer release, and the same values into the Cilium and Argo CD releases
3. **The installer's Application** → carries the set in `valuesObject` to `charts/argocd-applications`
4. **Child Applications** → reference `{{ .Values.* }}`, resolved from that `valuesObject`, and pass the subset each component needs into its chart

Chart `values.yaml` files hold placeholders for the same keys. Helm requires the
file to exist, and `build.sh` uses the placeholders to render every chart
offline for review.

## Benefits

1. **Single Point of Configuration** - All environment-specific values are passed once to `argocd-applications`
2. **Automatic Propagation** - Values automatically flow to individual charts through templated `valuesObject` blocks
3. **Type Safety** - Helm validates that all referenced values exist
4. **Maintainability** - Adding a new value means three places: `module.cluster.app_of_apps_values`, the installer chart (`values.yaml` and its `valuesObject`), and the child Application that needs it.
5. **Separation of Concerns** - Terraform manages infrastructure values, Helm manages application deployment
6. **Debugging & Review** - `values.yaml` files enable generation of `rendered.yaml` files via `helm template`, making it easier to:
   - Debug template rendering issues
   - Review generated manifests in PRs
   - Validate complex Helm logic beyond simple interpolation
   - For third-party charts (ArgoCD, Cilium), review the complex resulting manifests even without final runtime values

## Adding a new propagated value

Three places, plus a regenerate:

1. **`module.cluster.app_of_apps_values`** (`tf/modules/talos-cluster/main.tf`) -- the real value
2. **`charts/argocd-applications-installer`** -- a placeholder in `values.yaml` and a line in the template's `valuesObject`
3. **The child Application** in `charts/argocd-applications/templates/` that needs it, in its own `valuesObject`

Then `./build.sh` to regenerate the `rendered.yaml` files.

Keeping (1) and (2) in step by hand is what issue #284 is about.

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

### 1. Non-sensitive configuration

**Source**: `tf/nodes` variables, per cluster in `test.tfvars` / `prod.tfvars`
**Propagation**: Terraform → installer `valuesObject` → argocd-applications → individual charts
**Examples**: `cluster_name`, `pod_cidr`, `external_ip_cidr`, `targetRevision`

These flow through the standard mechanism described above.

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

### 3. Values from the bootstrap layer

**Source**: `tf/bootstrap` remote state, read by `tf/nodes/remote.tf`
**Propagation**: Terraform → installer `valuesObject` → argocd-applications
**Examples**: `project_id`, which `tf/bootstrap` creates along with the GCP projects themselves

## Design Decisions

### What 1Password is still for

It is no longer the interface between Terraform and the cluster -- Terraform
passes values straight into the Helm releases it installs. What it still holds:

- **Secrets** the cluster pulls at runtime via `OnePasswordItem`, and the two
  operator credentials Terraform writes so the operator can serve them
- **Artifacts a human needs**: kubeconfig, talosconfig, the Argo CD admin login

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

Currently, items follow patterns like `{cluster_name}-kubeconfig` and `{cluster_name}-cert-manager-dns01-sa-key`. Consider:
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
