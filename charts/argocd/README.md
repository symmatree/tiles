# ArgoCD

## Overview

[ArgoCD](https://github.com/argoproj/argo-cd) is the GitOps continuous delivery tool that manages the deployment of all other components in the cluster. It provides declarative application management and synchronization, ensuring the cluster state matches the desired state defined in Git.

After initial bootstrap, ArgoCD manages itself through its own Application resource, enabling self-management and automated synchronization.

## Architecture

ArgoCD is deployed using the [ArgoCD Helm chart](https://github.com/argoproj/argo-helm) with the following key components:

- **Application Controller**: Monitors Git repositories and syncs applications to match desired state. Includes Prometheus metrics and ServiceMonitor for observability.

- **Repo Server**: Handles Git repository operations and includes a custom [Tanka](https://github.com/grafana/tanka) plugin for processing [Jsonnet](https://github.com/google/go-jsonnet)/Tanka environments.

- **Server**: Provides the web UI and API. Configured with:
  - Ingress via Cilium at `argocd.{cluster_name}.symmatree.com`
  - Google OAuth authentication via Dex
  - Exec feature enabled for pod terminal access
  - Status badge support

- **[Dex](https://github.com/dexidp/dex)**: OIDC provider for authentication, configured with Google OAuth connector.

- **Notifications Controller**: Sends alerts to Slack channels for application sync status changes, health degradation, and deployment events.

The deployment uses the app-of-apps pattern where the `argocd-applications` chart manages all other Application resources, including ArgoCD itself.

## Configuration

### Key Configuration Values

Configuration is managed through `values.yaml` and overridden via the Application's `valuesObject`:

- **Domain**: `argocd.{cluster_name}.symmatree.com` (set via `argo-cd.global.domain`)
- **gRPC Ingress Hostname**: `grpc-argocd.{cluster_name}.symmatree.com` (currently disabled)
- **Cluster Name**: Passed as `cluster_name` value
- **Vault Name**: Passed as `vault_name` value for 1Password integration
- **Target Revision**: Git branch/tag to track (passed as `targetRevision`)

### Environment-Specific Settings

- Domain configuration is cluster-specific and set during bootstrap
- OAuth credentials are stored in `google-oauth-secret` Kubernetes secret
- Slack notification token stored in `slack-token` secret (referenced by notifications controller)

### Dependencies

- **[cert-manager](../cert-manager/README.md)**: Required for TLS certificates on the ingress ([GitHub](https://github.com/cert-manager/cert-manager))
- **[external-dns](../external-dns/README.md)**: Required for DNS record creation for the ingress hostname ([GitHub](https://github.com/kubernetes-sigs/external-dns))
- **[Cilium](../cilium/README.md)**: Provides the ingress controller and CNI ([GitHub](https://github.com/cilium/cilium))
- **[OnePassword Operator](../onepassword/README.md)**: Used for secret management (GitHub repository credentials) ([GitHub](https://github.com/1Password/onepassword-operator))

## Prerequisites

### Required Secrets

- **google-oauth-secret**: Contains `OAUTH_CLIENT_ID` and `OAUTH_CLIENT_SECRET` for Google OAuth
- **slack-token**: Slack API token for notifications (referenced as `$slack-token` in notifications config)
- **GitHub repository secret**: For accessing private Git repositories (TODO: document secret name and format)

### Required Infrastructure

- Kubernetes cluster with control plane nodes
- Network connectivity to Git repositories
- DNS zone for cluster subdomain (managed by external-dns)

## Terraform Integration

N/A - ArgoCD is bootstrapped manually and does not have Terraform-managed resources.

## Application Manifest

- **Application**: [`application.yaml`](application.yaml)
- **Helm Chart**: Uses the `charts/argocd` directory as a Helm chart
- **Values**: [`values.yaml`](values.yaml)
- **Namespace**: `argocd`
- **Sync Policy**: Automated with prune and self-heal enabled
- **Sync Options**:
  - `CreateNamespace=true`
  - `ServerSideApply=true`
  - `FailOnSharedResource=true`

### Bootstrap Process

ArgoCD is initially bootstrapped via the CI workflow (`.github/workflows/bootstrap-cluster.yaml`) which runs [`bootstrap.sh`](bootstrap.sh):

1. Creates the `argocd` namespace with pod security labels
2. Runs `helm template` with cluster-specific values (loaded from 1Password)
3. Applies manifests via `kubectl apply --server-side`

After bootstrap, the `argocd-applications` chart installs the ArgoCD Application resource, which enables self-management. ArgoCD then syncs itself (mostly adding tracking annotations) and becomes self-managed.

**Note**: The ingress won't work properly until `external-dns` and `cert-manager` are running, but ArgoCD can operate headless via CLI during initial setup.

## Access & Endpoints

### Web UI

- **URL**: `https://argocd.{cluster_name}.symmatree.com`
- **Authentication**:
  - Local admin user (currently the only method, enabled by default)
  - Google OAuth via Dex (configured but not yet working - aspirational)
- **Initial Admin Password**: Generated by ArgoCD during installation. Retrieve from secret:

  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
  ```

  Note: The password is auto-generated and not easily set to a chosen value. The long-term goal is to get Google OAuth working, with the admin password as a rarely-used manual fallback.

### CLI Access

ArgoCD CLI can be used to access ArgoCD before ingress is functional:

```bash
# Port-forward to server
kubectl port-forward -n argocd svc/argocd-server 8080:443

# Login (use admin user and password from secret)
argocd login localhost:8080 --insecure
```

### API

- **gRPC**: Available on the server service (gRPC ingress currently disabled)
- **REST API**: Available via the server service and ingress

## Monitoring & Observability

### Metrics

- **Application Controller**: Exposes Prometheus metrics with ServiceMonitor enabled
- **Server**: Exposes Prometheus metrics with ServiceMonitor enabled
- **Dex**: Exposes Prometheus metrics with ServiceMonitor enabled
- **Alerts**: Defined by the ArgoCD mixin (see `argocd-mixin` Application)

### Dashboards

Grafana dashboards from the [ArgoCD mixin](../argocd-applications/templates/README-argocd-mixin.md):

- **Application**: Functional, displays application metrics and sync status
- **Operational**: Functional, displays operational metrics
- **Notifications**: No data (notifications controller may not be running or configured)

### Alerts

Prometheus alerts are defined by the [ArgoCD mixin](../argocd-applications/templates/README-argocd-mixin.md). The mixin provides comprehensive alerts for ArgoCD application sync status, health, and operational metrics. Alerts are deployed as PrometheusRule resources in the `argocd` namespace, discovered by Alloy, and pushed to Mimir's Ruler for evaluation.

### Logs

View component logs:

```bash
# Application controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller

# Server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server

# Repo server logs (includes Tanka plugin output)
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server

# Dex logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-dex-server
```

## Troubleshooting

### Common Issues

**Ingress not working after bootstrap:**

- Verify cert-manager is running and can issue certificates
- Verify external-dns is running and can create DNS records
- Check ingress resource: `kubectl get ingress -n argocd`
- Check certificate status: `kubectl get certificate -n argocd`

**Applications not syncing:**

- Check application status: `kubectl get application -n argocd`
- View application details: `kubectl describe application <app-name> -n argocd`
- Check application controller logs for sync errors (see Logs section above)

**Tanka plugin not working:**

- Verify repo server pod is running: `kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-repo-server`
- Check repo server logs for plugin errors (see Logs section above)
- Verify `cmp-tanka` ConfigMap exists: `kubectl get configmap -n argocd cmp-tanka`
- Check plugin generate script: `kubectl get configmap -n argocd cmp-tanka -o yaml`

**OAuth not working:**

- Note: OAuth is currently not functional (work in progress)
- Verify `google-oauth-secret` exists: `kubectl get secret -n argocd google-oauth-secret`
- Check Dex pod logs (see Logs section above)
- Verify OAuth credentials are correct in the secret

### Health Checks

- Verify all pods are running: `kubectl get pods -n argocd`
- Check application controller health: `kubectl get application -n argocd` (all should show Synced/Healthy)
- Check server readiness: `kubectl get endpoints -n argocd argocd-server`

## Maintenance

### Update Procedures

Previously, ArgoCD was deployed as an umbrella chart with a `Chart.yaml` containing dependencies that Dependabot could automatically upgrade. Now that it's a single Application resource, updates require:

- **Helm Chart Version**: Update the `targetRevision` in `application.yaml` to point to the desired Git branch/tag
- **ArgoCD Version**: Update the Helm chart version in `values.yaml` (if using a versioned chart) or update the chart source

**Note**: A tool needs to be created or found to automatically update `application.yaml` files (similar to how Dependabot updated `Chart.yaml` dependencies). This is work in progress.

### Backup Requirements

All ArgoCD configuration is defined as code in Git and can be recreated from the repository. All secrets (including `google-oauth-secret`, `slack-token`, and GitHub repository credentials) are managed via OnePasswordItem CRDs that sync from 1Password. Runtime state (application sync status, etc.) is ephemeral and recreated automatically by ArgoCD on startup.

**No Kubernetes resource backups are needed for ArgoCD** - everything can be recreated from Git and 1Password.

### Known Limitations

- Tanka plugin downloads `jb` and `tk` binaries on repo server startup rather than using a pre-built image
- gRPC ingress is disabled (not currently needed for CLI access)
- GitHub repository secret must be created manually (not automated in bootstrap)

## Custom Tanka Plugin

ArgoCD includes a custom ConfigManagementPlugin for Tanka/Jsonnet support:

- **ConfigMap**: `cmp-tanka` defines the plugin configuration
- **Implementation**: `charts/argocd/templates/tanka.yaml`
- **Repo Server Container**: Extra container in repo server pod that installs `jb` ([jsonnet-bundler](https://github.com/jsonnet-bundler/jsonnet-bundler)) and `tk` ([tanka](https://github.com/grafana/tanka)) binaries
- **Plugin Discovery**: Looks for `./environments/*/main.jsonnet` files
- **Generation**: Uses `tk show` with environment-specific parameters

The plugin allows ArgoCD to manage Tanka environments (like `apprise` and `odm`) as Application resources, using Tanka to render Jsonnet into Kubernetes manifests.
