# Apprise

## Overview

[Apprise](https://github.com/caronc/apprise-api) is a notification delivery service that provides centralized routing for notifications from cluster services. It supports multiple notification backends (Slack, email, SMS, etc.) and allows services to send notifications through a single API endpoint rather than managing individual notification configurations.

Apprise provides two tiers of notification delivery:

- **Centralized service**: Most services route notifications through the shared Apprise API service
- **Key services**: Critical services can use Apprise directly (CLI/library) or as a sidecar for maximum robustness

## Architecture

Apprise is deployed using Tanka/Jsonnet as a single instance with:

- **Apprise API**: Main notification service container
- **Nginx**: Reverse proxy with authentication
- **PVCs**: Two persistent volumes for configuration and attachments
- **Ingress**: External access with TLS via cert-manager

### Notification Routing

Notifications are routed using tags:

- **Bond**: For house-related things
- **Tales**: For the cluster and internal stuff
- **Priority**: Things that need immediate attention

Most notifications are delivered via Slack with an echo to Gmail (via app-password) for posterity, since free Slack doesn't keep long-term archives.

## Configuration Values

### Key Configuration Values

Configuration is managed through the Application's plugin parameters:

- **Hostname**: `apprise.{cluster_name}.symmatree.com`
- **Cluster Issuer**: `real-cert` (for TLS certificates)
- **Apprise Env Secret**: `{cluster_name}-apprise-env` (1Password item)
- **Apprise Admin Secret**: `{cluster_name}-apprise-admin` (1Password item)

### Environment-Specific Settings

- Cluster name, vault name, and project ID are cluster-specific and set via Terraform/bootstrap process

### Dependencies

- **[cert-manager](../../../charts/cert-manager/README.md)**: Required for TLS certificates
- **[external-dns](../../../charts/external-dns/README.md)**: Required for DNS record creation
- **[OnePassword Operator](../../../charts/onepassword/README.md)**: Required for syncing secrets from 1Password
- **[Cilium](../../../charts/cilium/README.md)**: Provides ingress controller

## Prerequisites

### Required Components

- **cert-manager**: Must be installed and configured
- **external-dns**: Must be running for DNS record creation
- **OnePassword Operator**: Must be installed and configured

### Required Secrets

- **Apprise Env**: Stored in 1Password as `{cluster_name}-apprise-env`
  - Created by Terraform (`tf/modules/k8s-cluster/apprise.tf`)
  - Contains `SECRET_KEY` for Apprise API
- **Apprise Admin**: Stored in 1Password as `{cluster_name}-apprise-admin`
  - Created by Terraform (`tf/modules/k8s-cluster/apprise.tf`)
  - Contains admin username/password and `.htpasswd` file
- **Apprise Config**: Stored in 1Password as `apprise-config` (manually created)
  - Contains notification service configuration (Slack, Gmail, etc.)
  - Must be pasted into the Apprise UI if it gets wiped

### Required Infrastructure

- **DNS Zone**: `{cluster_name}.symmatree.com` must be managed by external-dns
- **TLS Certificate**: Managed by cert-manager

## Terraform Integration

- **Terraform Module**: `tf/modules/k8s-cluster/apprise.tf`
- **Resources Created**:
  - Random password for `SECRET_KEY` (stored in 1Password `{cluster_name}-apprise-env`)
  - Random password for admin user (stored in 1Password `{cluster_name}-apprise-admin`)
  - `.htpasswd` file for admin authentication

## Application Manifest

- **Application**: [`application.yaml`](application.yaml)
- **Tanka Environment**: `tanka/environments/apprise/`
- **Main Jsonnet**: [`main.jsonnet`](main.jsonnet)
- **Namespace**: `apprise`
- **Sync Policy**: Automated with prune and self-heal enabled
- **Sync Options**:
  - `CreateNamespace=true`
  - `ServerSideApply=true`

## Access & Endpoints

### Web UI

- **URL**: `https://apprise.{cluster_name}.symmatree.com`
- **Configuration UI**: `https://apprise.{cluster_name}.symmatree.com/cfg/apprise`
- **Authentication**: Admin user (credentials from 1Password `{cluster_name}-apprise-admin` item)
- **TLS**: Managed by cert-manager

### API Endpoint

- **Internal**: `http://apprise.apprise.svc:8000` (accessible from cluster without authentication)
- **External**: `https://apprise.{cluster_name}.symmatree.com` (requires authentication)

## Monitoring & Observability

### Metrics

- TODO: Document if Apprise exposes metrics

### Dashboards

- TODO: Document if Apprise has dashboards

### Logs

View Apprise logs:

```bash
# View Apprise pod logs
kubectl logs -n apprise -l app=apprise
```

## Troubleshooting

### Common Issues

**Apprise not accessible:**

- Verify ingress is created: `kubectl get ingress -n apprise`
- Check certificate status: `kubectl get certificate -n apprise`
- Verify external-dns created DNS record
- Check Apprise pod is running: `kubectl get pods -n apprise`

**Notifications not being delivered:**

- Verify Apprise config is loaded: Check the configuration UI
- Check Apprise pod logs for delivery errors
- Verify notification service credentials (Slack token, Gmail app-password, etc.)
- Test notification delivery via the Apprise UI

**Authentication failures:**

- Verify admin secret exists: `kubectl get secret {cluster_name}-apprise-admin -n apprise`
- Check `.htpasswd` file is correct in the secret
- Verify OnePasswordItem is synced: `kubectl get onepassworditem {cluster_name}-apprise-admin -n apprise`

**Config lost:**

- Apprise config is stored in PVC and may be lost if PVC is deleted
- Restore from 1Password `apprise-config` item via the configuration UI
- TODO: Move config to a proper provisioned secret

### Health Checks

- Verify Apprise pod is running: `kubectl get pods -n apprise`
- Check Application is synced: `kubectl get application apprise -n argocd`
- Test web UI access: Navigate to `https://apprise.{cluster_name}.symmatree.com`
- Test API endpoint: `curl http://apprise.apprise.svc:8000/status` (from within cluster)

## Maintenance

### Update Procedures

- Update Apprise image version in `main.jsonnet`
- ArgoCD will automatically sync changes
- Note: Apprise updates may require pod restarts

### Backup Requirements

- **Apprise Config**: Stored in PVC, should be backed up from 1Password `apprise-config` item
- **Admin Credentials**: Stored in 1Password, backed up there
- **Environment Secret**: Stored in 1Password, backed up there

### Known Limitations

- **Config Storage**: Apprise config is stored in PVC and may be lost if PVC is deleted (should be moved to a provisioned secret)
- **Single Instance**: Apprise runs as a single instance (no HA)

## Usage

### Sending Notifications

Services can send notifications to Apprise via:

1. **HTTP API**: `POST http://apprise.apprise.svc:8000/notify/{service}` (internal, no auth)
2. **HTTP API**: `POST https://apprise.{cluster_name}.symmatree.com/notify/{service}` (external, requires auth)
3. **Direct CLI/Library**: For key services, Apprise can be called directly with config from a secret
4. **Sidecar Container**: For key services, Apprise API can run as a sidecar in the same pod

### Configuration Management

Apprise configuration is managed via the web UI at `https://apprise.{cluster_name}.symmatree.com/cfg/apprise`. The configuration YAML is stored in 1Password `apprise-config` item and should be pasted back into the UI if it gets wiped.

### Key Services Pattern

For critical services that need maximum robustness:

- **Direct CLI/Library**: Call Apprise directly with config injected from a secret (config must be pre-injected)
- **Sidecar Container**: Run Apprise API as a sidecar in the same pod (better isolation, but adds complexity)

Both patterns offer similar security and robustness, with the choice depending on ease of adding binaries/config versus adding a sidecar container.
