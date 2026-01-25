# static-certs

## Overview

The `static-certs` chart manages one-off TLS certificates for external resources (not associated with Kubernetes ingresses). It uses [cert-manager](../cert-manager/README.md) to issue and manage certificates for home network resources that need TLS certificates but aren't running in the cluster.

This chart creates cert-manager `Certificate` resources that cert-manager uses to issue certificates via Let's Encrypt, storing them as Kubernetes secrets that can be manually extracted and deployed to external systems.

## Architecture

The chart uses a Helm template to generate cert-manager `Certificate` resources from a list in `values.yaml`. Each certificate:

- Uses the `real-cert` ClusterIssuer (Let's Encrypt production)
- Creates a Kubernetes secret with the certificate and key
- Uses ECDSA P-384 keys
- Has automatic rotation enabled
- Is stored in the `static-certs` namespace

### Certificate Naming

Certificates are named using the pattern: `{name}{subdomain}.{baseDomain}`

- **Base Domain**: `local.symmatree.com` (or `ad.local.symmatree.com` for AD domain)
- **Subdomain**: Optional (e.g., `.ad` for `raconteur.ad.local.symmatree.com`)
- **Name**: The service name (e.g., `morpheus`, `homeassistant`)

## Configuration

### Key Configuration Values

Configuration is managed through `values.yaml`:

- **Base Domain**: `baseDomain` - Base domain for certificates (default: `local.symmatree.com`)
- **Cluster Issuer**: `clusterIssuer` - cert-manager ClusterIssuer to use (default: `real-cert`)
- **Namespace**: `namespace` - Namespace for certificates (default: `static-certs`)
- **Static Certs**: `staticCerts` - List of certificates to create
  - `name`: Certificate name (also used in DNS name)
  - `subdomain`: Optional subdomain prefix (e.g., `.ad`)

### Current Certificates

Certificates currently managed:

- **raconteur**: `raconteur.ad.local.symmatree.com`
- **morpheus**: `morpheus.local.symmatree.com`
- **homeassistant**: `homeassistant.local.symmatree.com`
- **hubitat**: `hubitat.local.symmatree.com`
- **cam**: `cam.local.symmatree.com`
- **photos**: `photos.local.symmatree.com`
- **laserjet**: Special handling (see Special Cases section)

### Environment-Specific Settings

No environment-specific configuration needed - all certificates use the same base domain and issuer.

### Dependencies

- **[cert-manager](../cert-manager/README.md)**: Required for certificate issuance and management
- **[external-dns](../external-dns/README.md)**: Required for DNS record management (cert-manager needs DNS records for DNS01 challenges)

## Prerequisites

### Required Secrets

- **laserjet-cert-password**: 1Password item at `vaults/tiles-secrets/items/laserjet-cert-password` (for laserjet certificate special handling)

### Required Infrastructure

- **DNS Zone**: `local.symmatree.com` (or `ad.local.symmatree.com`) must be managed by external-dns
- **Let's Encrypt**: `real-cert` ClusterIssuer must be configured and working

## Terraform Integration

N/A - static-certs does not have Terraform-managed resources.

## Application Manifest

- **Application**: [`application.yaml`](application.yaml)
- **Helm Chart**: Uses `charts/static-certs` directory as a Helm chart
- **Templates**: [`templates/`](templates/) - Contains certificate templates
- **Namespace**: `static-certs`
- **Sync Policy**: Automated with prune and self-heal enabled
- **Sync Options**:
  - `CreateNamespace=true`
  - `ServerSideApply=true`

## Access & Endpoints

N/A - This chart only creates certificate resources. Certificates are accessed via Kubernetes secrets.

## Monitoring & Observability

### Metrics

N/A - This chart only creates certificate resources. Monitor cert-manager for certificate status.

### Dashboards

N/A - No dashboards specific to this component.

### Logs

View certificate status:

```bash
# List all certificates
kubectl get certificates -n static-certs

# View certificate details
kubectl describe certificate <name> -n static-certs

# Check certificate status
kubectl get certificate <name> -n static-certs -o yaml
```

## Troubleshooting

### Common Issues

**Certificates not issuing:**

- Verify cert-manager is running: `kubectl get pods -n cert-manager`
- Check certificate status: `kubectl describe certificate <name> -n static-certs`
- Verify ClusterIssuer exists: `kubectl get clusterissuer real-cert`
- Check DNS records exist for the domain (cert-manager needs DNS01 challenges)
- Review cert-manager logs for errors

**Certificate secrets not created:**

- Verify certificate is ready: `kubectl get certificate <name> -n static-certs`
- Check certificate status conditions: `kubectl get certificate <name> -n static-certs -o yaml | grep -A 10 conditions`
- Verify secret exists: `kubectl get secret <name>-cert -n static-certs`

**DNS challenges failing:**

- Verify external-dns is running and managing DNS records
- Check DNS records exist: `dig TXT _acme-challenge.<domain>`
- Verify DNS zone is accessible to cert-manager

### Health Checks

- Verify certificates exist: `kubectl get certificates -n static-certs`
- Check certificates are ready: `kubectl get certificates -n static-certs -o jsonpath='{.items[*].status.conditions[*].type}'`
- Verify Application is synced: `kubectl get application static-certs -n argocd`

## Maintenance

### Update Procedures

- Add/remove certificates by editing `values.yaml` `staticCerts` list
- ArgoCD will automatically sync changes
- cert-manager will automatically issue new certificates

### Backup Requirements

- **Certificate Secrets**: Stored in Kubernetes secrets, can be recreated by cert-manager
- **Certificate Configuration**: Stored in Git (values.yaml), backed up there

### Known Limitations

- **Manual Deployment**: Certificates must be manually extracted and deployed to external systems
- **No Automation**: No automatic deployment to external systems (requires manual or script-based deployment)
- **Special Cases**: Some certificates (like laserjet) require special handling

## Usage

### Extracting Certificates

Certificates are stored as Kubernetes secrets. To extract them for use on external systems:

```bash
export NAME=morpheus
kubectl get secret -n static-certs ${NAME}-cert -o jsonpath="{.data['tls\.crt']}" | base64 --decode > ${NAME}-cert.crt
kubectl get secret -n static-certs ${NAME}-cert -o jsonpath="{.data['tls\.key']}" | base64 --decode > ${NAME}-cert.key
```

**Note**: On macOS, use `base64 -d` instead of `base64 --decode`. If you have `k` aliased to `kubectl`, you can use `k` instead.

### Adding New Certificates

1. Add the certificate to `values.yaml` `staticCerts` list:
   ```yaml
   staticCerts:
     - name: newservice
       subdomain: .ad  # Optional
   ```

2. Commit and push changes
3. ArgoCD will automatically sync and cert-manager will issue the certificate

### Special Cases

**laserjet**: Requires special handling (password-protected certificate). See `templates/laserjet.yaml` for details. Requires 1Password item `laserjet-cert-password`.

## Certificate Details

All certificates use:
- **Algorithm**: ECDSA P-384
- **Encoding**: PKCS1
- **Rotation Policy**: Always (automatic rotation)
- **Revision History**: 2 (keeps last 2 certificate revisions)

Certificates are issued via Let's Encrypt using DNS01 challenges, requiring:
- DNS records managed by external-dns
- cert-manager with `real-cert` ClusterIssuer configured
- DNS zones accessible to cert-manager
