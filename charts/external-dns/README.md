# external-dns

## Overview

[external-dns](https://github.com/kubernetes-sigs/external-dns) automatically synchronizes Kubernetes ingress and service resources with Google Cloud DNS, managing DNS records for cluster services. It watches for ingress and service resources and creates/updates A and AAAA records in Google Cloud DNS zones.

external-dns works alongside cert-manager: cert-manager creates TXT records for ACME challenges, while external-dns manages A/AAAA records for service endpoints.

## Architecture

external-dns is deployed using the [external-dns Helm chart](https://github.com/kubernetes-sigs/external-dns/tree/master/charts/external-dns) with the following configuration:

- **Provider**: Google Cloud DNS
- **Sources**: Watches `ingress` and `service` resources
- **Registry**: TXT records (stores ownership information in TXT records)
- **Policy**: `upsert-only` - Only creates/updates records, never deletes them
- **Interval**: 1 minute - Checks for changes every minute

### Domain Filters

external-dns is configured to manage DNS records in:

- **`{cluster_name}.symmatree.com`**: Cluster's main domain zone
- **`0.10.in-addr.arpa`**: Reverse DNS zone for 10.0.0.0/8 network

### ACME Challenge Exclusion

external-dns excludes ACME challenge domains (containing `_acme-challenge.`) because:

- They contain underscores, which are not valid in IDNA domain names
- They are managed by cert-manager for DNS01 challenges

## Configuration

### Key Configuration Values

Configuration is managed through `values.yaml` and overridden via the Application's `valuesObject`:

- **TXT Owner ID**: `txtOwnerId` - Identifier for this external-dns instance (set to cluster name)
- **Domain Filters**: `domainFilters` - List of domains to manage
- **Google Project**: `extraArgs[--google-project]` - Google Cloud project ID
- **ACME Exclusion**: `extraArgs[--regex-domain-exclusion]` - Excludes `_acme-challenge.` domains
- **Policy**: `upsert-only` - Only creates/updates, never deletes
- **Registry**: `txt` - Uses TXT records for ownership tracking
- **Interval**: `1m` - Check interval for DNS updates

### Environment-Specific Settings

- Cluster name, project ID, and vault name are cluster-specific and set via Terraform/bootstrap process

### Dependencies

- **[cert-manager](../cert-manager/README.md)**: Works alongside cert-manager (cert-manager manages TXT records for ACME, external-dns manages A/AAAA records)
- **OnePassword Operator**: Required for syncing Google Cloud DNS service account key from 1Password

## Prerequisites

### Required Components

- **OnePassword Operator**: Must be installed and configured
- **Google Cloud DNS**: DNS zones must exist and be accessible

### Required Secrets

- **Google Cloud DNS Service Account Key**: Stored in 1Password as `{cluster_name}-external-dns-clouddns-sa-key`
  - Created by Terraform (`tf/modules/k8s-cluster/external-dns.tf`)
  - Synced to Kubernetes via OnePasswordItem CRD as `clouddns-sa` secret

### Required Infrastructure

- **Google Cloud Service Account**: Created by Terraform with DNS admin permissions
  - Project-level DNS reader role (to list zones)
  - Zone-level DNS admin role for `{cluster_name}.symmatree.com` zone
- **Google Cloud DNS Zones**: Must exist before external-dns can manage records

## Terraform Integration

- **Terraform Module**: `tf/modules/k8s-cluster/external-dns.tf`
- **Resources Created**:
  - Google Cloud service account for DNS management
  - IAM bindings for DNS zone access
  - Service account key stored in 1Password

## Application Manifest

- **Application**: [`application.yaml`](application.yaml)
- **Helm Chart**: Uses `charts/external-dns` directory as a Helm chart
- **Templates**: [`templates/`](templates/) - Contains OnePasswordItem for service account key
- **Namespace**: `external-dns`
- **Sync Policy**: Automated with prune and self-heal enabled
- **Sync Options**:
  - `CreateNamespace=true`
  - `ServerSideApply=true`

## Access & Endpoints

N/A - external-dns is a controller with no user-facing endpoints. DNS records are managed automatically.

## Monitoring & Observability

### Metrics

- **Prometheus ServiceMonitor**: Enabled - external-dns exposes Prometheus metrics
- Metrics endpoint: Available on external-dns service

### Dashboards

- TODO: Document if external-dns mixin provides dashboards

### Alerts

- TODO: Document external-dns alerts (if any)

### Logs

View external-dns logs:

```bash
# View external-dns pod logs
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns
```

## Troubleshooting

### Common Issues

**DNS records not being created:**

- Verify external-dns pod is running: `kubectl get pods -n external-dns`
- Check external-dns logs for errors (see Logs section above)
- Verify service account secret exists: `kubectl get secret clouddns-sa -n external-dns`
- Check service account has DNS permissions in Google Cloud
- Verify domain filters match the ingress/service hostnames
- Check ingress/service annotations are correct (if using annotations)

**DNS records not updating:**

- external-dns uses `upsert-only` policy, so it won't delete records
- Check external-dns logs for update attempts
- Verify TXT ownership records exist (external-dns uses TXT records to track ownership)
- Check for conflicts with manual DNS records

**ACME challenge records appearing:**

- Verify ACME exclusion regex is working: `--regex-domain-exclusion=^_acme-challenge\.`
- Check external-dns logs to see if it's attempting to manage ACME records
- cert-manager should manage ACME challenge records, not external-dns

**Permission errors:**

- Verify service account has DNS admin role on the zone
- Check service account key is valid and not expired
- Verify Google Cloud project ID is correct

### Health Checks

- Verify external-dns pod is running: `kubectl get pods -n external-dns`
- Check Application is synced: `kubectl get application external-dns -n argocd`
- Test DNS record creation: Create an ingress and verify DNS record appears in Google Cloud DNS
- Check TXT ownership records: Look for TXT records with external-dns ownership information

## Maintenance

### Update Procedures

- Update external-dns chart version in `values.yaml` or Chart.yaml
- ArgoCD will automatically sync changes
- Note: external-dns updates may require pod restarts

### Backup Requirements

- **Service Account Key**: Managed in 1Password, backed up there
- **DNS Records**: Managed in Google Cloud DNS, backed up there
- **TXT Ownership Records**: Managed by external-dns, recreated automatically if needed

### Known Limitations

- **upsert-only policy**: external-dns will not delete DNS records, even if the ingress/service is deleted
- **TXT record ownership**: external-dns uses TXT records to track ownership, which may clutter DNS zones
- **ACME challenge exclusion**: ACME challenge domains are excluded but may still appear if regex doesn't match
- **Domain filter restrictions**: Only manages records in configured domain filters

## Usage

### How It Works

external-dns watches for:

- **Ingress resources**: Creates A/AAAA records for ingress hostnames
- **Service resources**: Creates A/AAAA records for LoadBalancer services with external IPs

When an ingress or service is created/updated, external-dns:

1. Checks if the hostname matches domain filters
2. Creates/updates A/AAAA records in Google Cloud DNS
3. Creates/updates TXT ownership records to track management

### Examples

- **ArgoCD ingress**: `argocd.{cluster_name}.symmatree.com` → A record pointing to ingress IP
- **Hubble UI ingress**: `hubble.{cluster_name}.symmatree.com` → A record pointing to ingress IP
- **LoadBalancer services**: External IPs → A records for service hostnames

### Interaction with cert-manager

- **cert-manager**: Creates TXT records for `_acme-challenge.{domain}` for DNS01 challenges
- **external-dns**: Creates A/AAAA records for service hostnames, excludes ACME challenge domains
- Both work together to provide complete DNS management for cluster services
