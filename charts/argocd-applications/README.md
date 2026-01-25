# ArgoCD Applications

## Overview

The `argocd-applications` chart implements the [ArgoCD app-of-apps pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/#app-of-apps-pattern), serving as the root application that manages all other Application resources in the cluster. It propagates configuration values from Terraform outputs (via bootstrap) to all downstream applications, providing a single point of configuration for environment-specific values.

## Architecture

The chart uses a Helm-based approach where:

- **Main Application** (`application.yaml.tmpl`): Defines the `argocd-applications` Application resource itself, which references this Helm chart
- **Templates Directory** (`templates/`): Contains Application resource templates for all components, either:
  - Symlinked from individual chart directories (e.g., `argocd-application.yaml` from `charts/argocd/application.yaml`)
  - Defined directly in templates (e.g., `alloy-application.yaml`, `grafana-application.yaml`)
- **Values Propagation**: The main Application's `valuesObject` contains the union of all values needed by downstream applications, which are then templated into each component's Application resource

### Value Flow

1. **Bootstrap** (`charts/bootstrap.sh`) receives values from Terraform/1Password and passes them to this chart via Helm `--set` arguments
2. **Main Application** (`application.yaml.tmpl`) receives values in its `valuesObject` block
3. **Template Files** reference `{{ .Values.* }}` which resolve to the parent chart's values
4. **Component Applications** receive values via their own `valuesObject` blocks in the rendered templates

This enables a single point of configuration where all environment-specific values (cluster name, NFS paths, project IDs, etc.) are passed once and automatically propagate to all components.

## Configuration

### Key Configuration Values

The main Application's `valuesObject` contains all values needed by downstream applications:

- `targetRevision`: Git branch/tag to track for all applications
- `cluster_name`: Cluster identifier used for domains, namespaces, and resource naming
- `vault_name`: 1Password vault name for secret management
- `pod_cidr`: Pod network CIDR (used by some networking components)
- `external_ip_cidr`: External IP CIDR range (used by Cilium)
- `project_id`: Google Cloud project ID
- `seed_project_id`: Seed project ID (for multi-project setups)
- `cluster_nfs_path`: NFS path for cluster storage (Loki, Mimir)
- `datasets_nfs_path`: NFS path for datasets (ODM)
- `nfs_server`: NFS server hostname/IP

### Environment-Specific Settings

All values are cluster-specific and set during bootstrap. The chart itself uses placeholder values in `values.yaml` for:

- Helm requirement (Helm 4.0.0+ requires at least an empty `values.yaml`)
- Documentation of expected value structure
- Rendered YAML generation for debugging and PR review

### Dependencies

- **[ArgoCD](../argocd/README.md)**: Must be installed and running before this chart can manage applications

## Prerequisites

All configuration values are provided by the bootstrap process from Terraform/1Password: `targetRevision`, `cluster_name`, `vault_name`, `pod_cidr`, `external_ip_cidr`, `project_id`, `seed_project_id`, `cluster_nfs_path`, `datasets_nfs_path`, and `nfs_server`.

## Terraform Integration

N/A - This chart receives values from Terraform outputs via the bootstrap process, but does not have direct Terraform integration.

## Application Manifest

- **Application Template**: [`application.yaml.tmpl`](application.yaml.tmpl) - Processed during bootstrap to create the main Application resource
- **Helm Chart**: Uses the `charts/argocd-applications` directory as a Helm chart
- **Values**: [`values.yaml`](values.yaml) - Contains placeholder values for documentation and rendering
- **Templates**: [`templates/`](templates/) - Contains Application resource templates for all components
- **Namespace**: `argocd` (where the main Application resource is created)

### Bootstrap Process

The `argocd-applications` chart is installed during cluster bootstrap (see `.github/workflows/bootstrap-cluster.yaml`) after Cilium and ArgoCD:

1. Bootstrap script receives values from Terraform/1Password
2. Runs `helm template` with cluster-specific values
3. Processes `application.yaml.tmpl` to create the main Application resource
4. Applies the Application resource via `kubectl apply`
5. ArgoCD syncs the Application, which then creates all component Application resources

Once installed, the chart is self-managed by ArgoCD and automatically syncs changes from Git.

## Access & Endpoints

N/A - This is a management component with no user-facing endpoints. View managed applications in the ArgoCD UI.

## Monitoring & Observability

### Metrics

N/A - This chart only creates Application resources; it does not run any pods or expose metrics.

### Dashboards

N/A - No dashboards specific to this component.

### Logs

View the main Application resource status:

```bash
# Check main Application status
kubectl get application argocd-applications -n argocd

# View all managed applications
kubectl get application -n argocd

# View Application details
kubectl describe application argocd-applications -n argocd
```

## Troubleshooting

### Common Issues

**Applications not being created:**

- Verify the main Application is synced: `kubectl get application argocd-applications -n argocd`
- Check Application sync status: `kubectl describe application argocd-applications -n argocd`
- Verify ArgoCD can access the Git repository
- Check ArgoCD application controller logs: `kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller`

**Template values not resolving:**

- Verify values are passed correctly in `application.yaml.tmpl` `valuesObject`
- Check that template files use `{{ .Values.* }}` syntax correctly
- Review rendered output: `helm template argocd-applications charts/argocd-applications --set cluster_name=test ...`

**Component applications failing to sync:**

- Check individual Application resources: `kubectl get application -n argocd`
- Verify component Application resources have correct `valuesObject` blocks
- Check that required values are present in the main Application's `valuesObject`

### Health Checks

- Verify main Application is synced: `kubectl get application argocd-applications -n argocd` (should show `Synced` and `Healthy`)
- Check all managed applications: `kubectl get application -n argocd` (all should show appropriate sync status)

## Maintenance

### Update Procedures

To add a new component:

1. Create or symlink the component's `application.yaml` in `templates/`
2. Add any required values to `application.yaml.tmpl` `valuesObject` if not already present
3. Add placeholder values to `values.yaml` for documentation
4. Update bootstrap workflow if new values need to be passed from Terraform
5. Commit and let ArgoCD sync the changes

To update existing components:

- Modify the component's Application template in `templates/`
- ArgoCD will automatically sync changes when committed to Git

### Backup Requirements

All configuration is defined as code in Git. The Application resources can be recreated from the repository. No backups needed.

### Known Limitations

- Template files must use Helm template syntax (`{{ .Values.* }}`) to reference parent chart values
- Values cannot be constructed in `values.yaml` (templates aren't expanded there) - use `valuesObject` in Application resources instead
- Adding new values requires updates in multiple places: `bootstrap.sh`, `application.yaml.tmpl`, `values.yaml`, and potentially component templates

## Template Structure

### Symlinked Templates

Some Application resources are symlinked from their component chart directories:

- `argocd-application.yaml` → `charts/argocd/application.yaml`
- `cilium-application.yaml` → `charts/cilium/application.yaml`
- `cert-manager-application.yaml` → `charts/cert-manager/application.yaml`
- etc.

This allows components to define their own Application resources while still receiving values from the parent chart.

### Direct Templates

Some Application resources are defined directly in `templates/`:

- `alloy-application.yaml`
- `grafana-application.yaml`
- `loki-application.yaml`
- `mimir-application.yaml`
- Mixin applications (argocd-mixin, cilium-mixin, etc.)
- Tanka-based applications (apprise, odm)

These are typically components that don't have their own chart directory or use different deployment methods (Tanka, direct Helm charts from external repos).

## Value Propagation Details

See [`docs/config-propagation.md`](../../docs/config-propagation.md) for detailed documentation on how values flow from Terraform through bootstrap to individual applications.
