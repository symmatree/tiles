# OnePassword Operator

## Overview

The [1Password Operator](https://github.com/1Password/onepassword-operator) synchronizes secrets from 1Password vaults into Kubernetes secrets, enabling secure secret management without storing credentials in Git. It consists of three components:

- **1Password Connect API**: Provides API access to 1Password vaults
- **1Password Connect Sync**: Syncs items from 1Password to the Connect API
- **1Password Operator**: Watches for `OnePasswordItem` CRDs and creates/updates Kubernetes secrets

This installation uses the [1Password Connect Helm chart](https://github.com/1Password/connect-helm-charts) to deploy all three components.

## Architecture

The operator is deployed using the 1Password Connect Helm chart with the following components:

- **Connect API**: Runs on control plane nodes, provides REST API for accessing 1Password vaults
- **Connect Sync**: Runs alongside Connect API, syncs items from 1Password
- **Operator**: Runs on control plane nodes, watches for `OnePasswordItem` CRDs and manages Kubernetes secrets

### OnePasswordItem CRD

Applications create `OnePasswordItem` custom resources to request secrets from 1Password:

```yaml
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: my-secret
  namespace: my-namespace
type: Opaque
spec:
  itemPath: vaults/my-vault/items/my-item
```

The operator watches for these resources and automatically creates/updates Kubernetes secrets with the data from the 1Password item.

## Configuration

### Key Configuration Values

Configuration is managed through `values.yaml`:

- **Connect API ServiceMonitor**: Enabled - Exposes Prometheus metrics
- **Connect API Ingress**: Disabled - No external access (reduces attack surface)
- **Operator**: Enabled - Deploys the operator component
- **Node Selectors**: All components run on control plane nodes
- **Tolerations**: All components tolerate control plane taints

### Environment-Specific Settings

No environment-specific configuration needed - the operator connects to 1Password using credentials stored in Kubernetes secrets.

### Dependencies

None - OnePassword Operator is a standalone component that other applications depend on.

## Prerequisites

### Required Components

None - OnePassword Operator is typically one of the first components installed.

### Required Secrets

The operator requires two secrets to be created during bootstrap (see Bootstrap section):

1. **`onepassword-token`**: Service account token for the operator to authenticate with 1Password
2. **`op-credentials`**: 1Password Connect credentials file (`1password-credentials.json`)

### Required Infrastructure

- **1Password Account**: With a vault containing the secrets to sync
- **1Password Connect Server**: Created in 1Password (provides the credentials file)
- **1Password Service Account**: With read access to the vault (provides the operator token)

## Terraform Integration

N/A - OnePassword Operator is bootstrapped via CI workflow. The secrets it syncs may be created by Terraform (e.g., service account keys), but the operator itself has no Terraform integration.

## Application Manifest

- **Application**: [`application.yaml`](application.yaml)
- **Helm Chart**: Uses `charts/onepassword` directory as a Helm chart (wraps 1Password Connect chart)
- **Templates**: [`templates/`](templates/) - Additional templates if any
- **Namespace**: `onepassword`
- **Sync Policy**: Automated with prune and self-heal enabled
- **Sync Options**:
  - `CreateNamespace=true`
  - `ServerSideApply=true`

## Bootstrap Process

The operator is bootstrapped via the CI workflow (`.github/workflows/bootstrap-cluster.yaml`) which runs [`make-secrets.sh`](make-secrets.sh) to create the initial secrets:

1. **Create namespace** (if it doesn't exist)
2. **Create `onepassword-token` secret**: Contains the 1Password service account token
3. **Create `op-credentials` secret**: Contains the 1Password Connect credentials file (base64 encoded)

The workflow loads the required secrets from 1Password:

- `onepassword_operator_token`: From `{cluster_name}-onepassword-operator` item
- `onepassword_connect_credentials`: From `{cluster_name}-onepassword-connect-credentials` item

### Initial Setup

1. Create a 1Password Connect server in your 1Password vault
2. Save the `1password-credentials.json` file to a 1Password item named `{cluster_name}-onepassword-connect-credentials`
3. Create a 1Password service account with read access to the vault, store the token in `{cluster_name}-onepassword-operator` item
4. Trigger the `bootstrap-cluster` workflow with the `onepassword` option enabled

## Access & Endpoints

- **Connect API**: Internal service only (ingress disabled)
- **Metrics**: Available via ServiceMonitor for Prometheus

## Monitoring & Observability

### Metrics

- **Prometheus ServiceMonitor**: Enabled - Connect API exposes Prometheus metrics
- Metrics endpoint: Available on Connect API service

### Dashboards

- TODO: Document if OnePassword mixin provides dashboards

### Alerts

- TODO: Document OnePassword alerts (if any)

### Logs

View operator component logs:

```bash
# Connect API logs
kubectl logs -n onepassword -l app.kubernetes.io/component=connect-api

# Connect Sync logs
kubectl logs -n onepassword -l app.kubernetes.io/component=connect-sync

# Operator logs
kubectl logs -n onepassword -l app.kubernetes.io/component=operator
```

## Troubleshooting

### Common Issues

**Secrets not syncing:**

- Verify OnePasswordItem CRD exists: `kubectl get crd onepassworditems.onepassword.com`
- Check OnePasswordItem status: `kubectl describe onepassworditem <name> -n <namespace>`
- Verify operator is running: `kubectl get pods -n onepassword -l app.kubernetes.io/component=operator`
- Check operator logs for errors (see Logs section above)
- Verify 1Password item path is correct in OnePasswordItem spec
- Check that service account token has access to the vault

**Connect API not responding:**

- Verify Connect API pod is running: `kubectl get pods -n onepassword -l app.kubernetes.io/component=connect-api`
- Check Connect API logs (see Logs section above)
- Verify `op-credentials` secret exists and is valid: `kubectl get secret op-credentials -n onepassword`
- Check Connect Sync is running: `kubectl get pods -n onepassword -l app.kubernetes.io/component=connect-sync`

**Authentication failures:**

- Verify `onepassword-token` secret exists: `kubectl get secret onepassword-token -n onepassword`
- Check token is valid and not expired in 1Password
- Verify service account has appropriate vault permissions

**Secret updates not propagating:**

- OnePasswordItem resources sync automatically, but there may be a delay
- Check operator logs for sync errors
- Verify the 1Password item was actually updated

### Health Checks

- Verify all pods are running: `kubectl get pods -n onepassword`
- Check OnePasswordItem resources: `kubectl get onepassworditems --all-namespaces`
- Verify Application is synced: `kubectl get application onepassword -n argocd`
- Test Connect API health: `kubectl exec -n onepassword <connect-api-pod> -- curl http://localhost:8080/health`

## Maintenance

### Update Procedures

- Update the 1Password Connect chart version in `Chart.yaml` or `values.yaml`
- ArgoCD will automatically sync changes
- Note: Operator updates may require restarting pods

### Backup Requirements

- **Service Account Token**: Stored in `onepassword-token` secret (can be regenerated in 1Password)
- **Connect Credentials**: Stored in `op-credentials` secret (should be backed up from 1Password item)
- **Synced Secrets**: All synced secrets originate from 1Password, so they're backed up there

### Known Limitations

- **Initial Bootstrap**: Requires bootstrap via CI workflow to create initial secrets
- **Token Rotation**: Service account tokens must be manually rotated by updating the `onepassword-token` secret
- **Vault Access**: Service account needs read access to vaults; consider using a separate privileged vault for the service account itself to avoid privilege escalation risks

## Usage Examples

### Creating a OnePasswordItem

Applications can request secrets by creating a OnePasswordItem resource:

```yaml
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: my-secret
  namespace: my-namespace
type: Opaque
spec:
  itemPath: vaults/my-vault/items/my-item
```

The operator will automatically create a Kubernetes secret named `my-secret` in the `my-namespace` namespace with the data from the 1Password item.

### Examples in This Cluster

- **cert-manager**: Uses OnePasswordItem to sync DNS01 service account key (see [`charts/cert-manager/templates/clouddns-sa-secret.yaml`](../cert-manager/templates/clouddns-sa-secret.yaml))
- **ArgoCD**: Uses OnePasswordItem to sync OAuth secrets and Slack tokens (see ArgoCD templates)

See [`docs/secrets.md`](../../docs/secrets.md) for more information on secret management in this cluster.
