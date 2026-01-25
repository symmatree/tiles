# cert-manager

## Overview

[cert-manager](https://github.com/cert-manager/cert-manager) is a Kubernetes certificate management controller that automates the issuance, renewal, and management of TLS certificates. It integrates with [Let's Encrypt](https://letsencrypt.org/) for public certificates and provides self-signed CA capabilities for internal certificates.

This installation includes [trust-manager](https://github.com/cert-manager/trust-manager) for distributing CA certificates to pods and managing trust bundles.

## Architecture

cert-manager is deployed using the [cert-manager Helm chart](https://github.com/cert-manager/cert-manager/tree/main/deploy/charts/cert-manager) with the following components:

- **cert-manager Controller**: Manages certificate lifecycle (issuance, renewal)
- **cert-manager Webhook**: Validates and mutates certificate resources
- **cert-manager CA Injector**: Injects CA certificates into webhook configurations
- **trust-manager**: Distributes CA certificates to pods via ConfigMaps or Secrets

### ClusterIssuers

The installation creates three ClusterIssuers (cluster-wide certificate issuers):

1. **`real-cert`**: Let's Encrypt production issuer for public certificates
   - Uses DNS01 challenges with Google Cloud DNS
   - Handles domains: `{cluster_name}.symmatree.com`, `ad.local.symmatree.com`, `local.symmatree.com`

2. **`staging-cert`**: Let's Encrypt staging issuer for testing
   - Same DNS zones as production
   - Useful for testing certificate issuance without hitting rate limits

3. **`{cluster_name}-ca-issuer`**: Self-signed CA issuer for internal certificates
   - Issues certificates signed by the cluster's self-signed CA
   - CA certificate is stored in `{cluster_name}-ca-tls` secret
   - Used for internal services that don't need public trust

### Certificate Trust Strategy

The cluster uses a centralized approach with one ClusterIssuer of each type to minimize the number of root certificates that need to be trusted on client machines. All ClusterIssuers are in the `cert-manager` namespace so trust-manager can access their secrets without requiring global secret read permissions.

## Configuration

### Key Configuration Values

Configuration is managed through `values.yaml` and overridden via the Application's `valuesObject`:

- **Cluster Name**: `cluster_name` - Used for ClusterIssuer names and CA certificate naming
- **Project ID**: `project_id` - Google Cloud project for DNS01 challenges (main project)
- **Seed Project ID**: `seed_project_id` - Google Cloud project for `ad.local` and `local` DNS zones
- **Vault Name**: `vault_name` - 1Password vault for DNS01 service account key

### DNS01 Configuration

- **DNS Recursive Nameservers**: `8.8.8.8:53,1.1.1.1:53` - External DNS servers for challenge propagation checks (required for Cilium/Talos setups where localhost DNS isn't available)
- **DNS01 Recursive Nameservers Only**: Enabled - Only use external nameservers, don't fall back to localhost

### Gateway API Support

- **Enable Gateway API**: `true` - Enables cert-manager to manage certificates for Gateway API resources (requires Cilium Gateway CRDs)

### Trust Manager Configuration

- **Secret Targets**: Enabled - Distributes CA certificates to pods
- **Authorized Secrets**: `{cluster_name}-ca-tls` - The cluster CA certificate secret that trust-manager is authorized to distribute

### Environment-Specific Settings

- Cluster name, project IDs, and vault name are cluster-specific and set via Terraform/bootstrap process

### Dependencies

- **[Cilium](../cilium/README.md)**: Required for Gateway API CRDs (if Gateway API is enabled)
- **OnePassword Operator**: Required for syncing DNS01 service account key from 1Password
- **external-dns**: Works alongside cert-manager for DNS management (cert-manager creates TXT records, external-dns manages A/AAAA records)

## Prerequisites

### Required Secrets

- **DNS01 Service Account Key**: Stored in 1Password as `{cluster_name}-cert-manager-dns01-sa-key`
  - Created by Terraform (`tf/modules/k8s-cluster/k8s-cert-manager.tf`)
  - Synced to Kubernetes via OnePasswordItem CRD

### Required Infrastructure

- **Google Cloud Service Account**: Created by Terraform with DNS admin permissions
  - Project-level DNS reader role (to list zones)
  - Zone-level DNS admin role for:
    - Main project: `{cluster_name}.symmatree.com` zone
    - Seed project: `ad.local.symmatree.com` and `local.symmatree.com` zones

## Terraform Integration

- **Terraform Module**: `tf/modules/k8s-cluster/k8s-cert-manager.tf`
- **Resources Created**:
  - Google Cloud service account for DNS01 challenges
  - IAM bindings for DNS zone access (main and seed projects)
  - Service account key stored in 1Password

## Application Manifest

- **Application**: [`application.yaml`](application.yaml)
- **Helm Chart**: Uses `charts/cert-manager` directory as a Helm chart
- **Templates**: [`templates/`](templates/) - Contains ClusterIssuers and secrets
- **Namespace**: `cert-manager`
- **Sync Policy**: Automated with prune and self-heal enabled
- **Sync Options**:
  - `CreateNamespace=true`
  - `ServerSideApply=true`
- **CRDs**: Skipped in Helm (installed separately) with `skipCrds: true`

## Access & Endpoints

N/A - cert-manager is a controller with no user-facing endpoints. Certificates are accessed via Kubernetes Secrets.

## Monitoring & Observability

### Metrics

- **Prometheus ServiceMonitor**: Enabled - cert-manager exposes Prometheus metrics
- Metrics endpoint: Available on cert-manager controller service

### Dashboards

- TODO: Document if cert-manager mixin provides dashboards

### Alerts

- TODO: Document cert-manager alerts (if any)

### Logs

View cert-manager component logs:

```bash
# Controller logs
kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager

# Webhook logs
kubectl logs -n cert-manager -l app.kubernetes.io/name=webhook

# CA Injector logs
kubectl logs -n cert-manager -l app.kubernetes.io/name=cainjector

# Trust Manager logs
kubectl logs -n cert-manager -l app.kubernetes.io/name=trust-manager
```

## Troubleshooting

### Common Issues

**Certificates not issuing:**

- Check ClusterIssuer status: `kubectl describe clusterissuer real-cert`
- Verify DNS01 service account secret exists: `kubectl get secret cert-manager-dns01-sa-key -n cert-manager`
- Check certificate status: `kubectl describe certificate <cert-name> -n <namespace>`
- Review certificate request: `kubectl get certificaterequest -n <namespace>`
- Check controller logs for errors (see Logs section above)

**DNS01 challenges failing:**

- Verify service account has DNS permissions in Google Cloud
- Check DNS zone names match configuration
- Verify external DNS servers are reachable (8.8.8.8, 1.1.1.1)
- Check DNS propagation: `dig TXT _acme-challenge.<domain>`
- Review controller logs for DNS challenge errors

**CA certificate not trusted:**

- Verify CA certificate secret exists: `kubectl get secret {cluster_name}-ca-tls -n cert-manager`
- Check trust-manager is distributing the certificate
- Re-trust the certificate on client machines (see Certificate Trust section below)

**Gateway API certificates not working:**

- Verify Gateway API CRDs are installed: `kubectl get crd gateways.gateway.networking.k8s.io`
- Check cert-manager has Gateway API enabled: `kubectl get deployment cert-manager -n cert-manager -o yaml | grep enableGatewayAPI`

### Health Checks

- Verify cert-manager pods are running: `kubectl get pods -n cert-manager`
- Check ClusterIssuers are ready: `kubectl get clusterissuers`
- Verify Application is synced: `kubectl get application cert-manager -n argocd`

## Maintenance

### Update Procedures

- Update cert-manager chart version in `values.yaml` or Chart.yaml
- ArgoCD will automatically sync changes
- Note: CRDs are installed separately and may need manual updates

### Backup Requirements

- **CA Certificate**: The `{cluster_name}-ca-tls` secret should be backed up if you need to re-trust the CA after cluster recreation
- **Let's Encrypt Account Keys**: Stored in `lets-encrypt-staging` and `lets-encrypt-real` secrets (automatically created)
- **DNS01 Service Account Key**: Managed in 1Password, backed up there

### Certificate Trust

The cluster CA certificate must be trusted on client machines to validate certificates issued by the `{cluster_name}-ca-issuer` ClusterIssuer. This needs to be redone whenever the cert-manager namespace or CA secret is deleted, or when the CA certificate is renewed (typically every few months).

#### Trust the CA Certificate on Ubuntu (e.g. WSL)

```bash
set -o pipefail
kubectl get secret {cluster_name}-ca-tls -n cert-manager \
  -o jsonpath="{.data.tls\.crt}" \
  | base64 -d \
  | sudo tee /usr/local/share/ca-certificates/{cluster_name}-ca-tls.crt \
&& sudo update-ca-certificates
```

#### Trust the CA Certificate in a Container

Many applications support providing a CA cert via values.yaml, which can be coupled with trust-manager to inject the cert as a ConfigMap (preferable) or Secret.

If you need to trust it at the OS level, mount the certificate file and configure the application to use it. For `distroless` containers, mount the certificate and point to it with an environment variable (see [example](https://github.com/symmatree/tales/blob/main/lgtm/values.yaml#L98)).

#### Trust the CA Certificate on Windows

The same `.crt` file can be installed on Windows using the `Certificates` `mmc.exe` snap-in.

**Get the certificate file:**

```bash
kubectl get secret {cluster_name}-ca-tls -n cert-manager \
  -o jsonpath="{.data.tls\.crt}" \
  | base64 -d > ca.crt
```

**Manually install:**

1. Windows-r `mmc.exe`
2. File / Add Remove Snap-in
3. Select Certificates, click Add, select My User Account, and hit Finish
4. Select Certificates, click Add, select Computer Account, Local Computer, and hit Finish
5. Import the certificate into your user Trusted Root Certificates, then drag it into Computer Account

**Install via Group Policy:**

See [Microsoft docs](https://learn.microsoft.com/en-us/windows-server/identity/ad-fs/deployment/distribute-certificates-to-client-computers-by-using-group-policy) for details. Create a new GPO under Domains / `ad.local.symmatree.com` / Group Policy Objects, import the cert, then link the GPO to the domain. Run `gpupdate /Force` on client machines to sync.

### Known Limitations

- CA certificate trust must be manually configured on client machines
- Let's Encrypt has rate limits (staging issuer helps with testing)
- DNS01 challenges require external DNS servers to be reachable (configured for Cilium/Talos)
