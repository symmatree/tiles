# Cilium Config

## Overview

The `cilium-config` chart provides additional cluster-specific configuration for [Cilium](https://github.com/cilium/cilium) using Cilium CRDs. It configures external IP pools and L2 announcement policies that complement the main Cilium installation.

This chart is separate from the main Cilium chart because neither Helm nor ArgoCD handle CRDs reliably when creating resources of a new CRD type in the same chart that installs those CRDs. Since Cilium is bootstrapped before ArgoCD exists, we're exposed to both Helm's and ArgoCD's CRD handling, and neither is consistent for this case. By separating the CRD resources (installed by Cilium) from the custom resources (created by this chart), we avoid these issues.

## Architecture

The chart creates two Cilium CRD resources:

- **CiliumLoadBalancerIPPool**: Defines the CIDR range for external IPs that can be assigned to LoadBalancer services
- **CiliumL2AnnouncementPolicy**: Configures L2 network announcements for service IPs, allowing services to be accessible on the local network

### L2 Announcement Policy

The `announce-everything` policy applies to all services (no selectors) and announces:

- **External IPs**: Service external IPs are announced on the L2 network
- **Load Balancer IPs**: LoadBalancer service IPs are announced on the L2 network

This allows services with external IPs or LoadBalancer type to be accessible from the local network without requiring an external load balancer.

## Configuration

### Key Configuration Values

Configuration is managed through the Application's `valuesObject`:

- **External IP CIDR**: `external_ip_cidr` - The CIDR range for external IPs (e.g., `10.0.128.0/18` for production cluster)
- **Target Revision**: `targetRevision` - Git branch/tag to track (passed through but not used in templates)

### Environment-Specific Settings

- External IP CIDR is cluster-specific and set via Terraform/bootstrap process
- The CIDR must match the cluster's external IP allocation

### Dependencies

- **[Cilium](../cilium/README.md)**: Must be installed and running (this chart creates Cilium CRDs that Cilium consumes)

## Prerequisites

- **Cilium**: Must be installed and running with Cilium CRDs available
- **External IP CIDR**: Must be provided from Terraform/bootstrap process

## Terraform Integration

N/A - This chart receives the `external_ip_cidr` value from Terraform outputs via the bootstrap process, but does not have direct Terraform integration.

## Application Manifest

- **Application**: [`application.yaml`](application.yaml)
- **Helm Chart**: Uses the `charts/cilium-config` directory as a Helm chart
- **Templates**: [`templates/`](templates/) - Contains Cilium CRD resources
- **Namespace**: `cilium` (same namespace as Cilium)
- **Sync Policy**: Automated with prune and self-heal enabled
- **Sync Options**:
  - `CreateNamespace=true`
  - `ServerSideApply=true`

## Access & Endpoints

N/A - This is a configuration component with no user-facing endpoints.

## Monitoring & Observability

### Metrics

N/A - This chart only creates configuration resources; it does not run any pods or expose metrics.

### Dashboards

N/A - No dashboards specific to this component. External IP and LoadBalancer IP usage can be viewed in Cilium dashboards.

### Logs

View the Cilium resources created by this chart:

```bash
# View LoadBalancer IP pool
kubectl get ciliumloadbalancerippool -n cilium

# View L2 announcement policy
kubectl get ciliuml2announcementpolicy -n cilium

# View details
kubectl describe ciliumloadbalancerippool lb-externalip-pool -n cilium
kubectl describe ciliuml2announcementpolicy announce-everything -n cilium
```

## Troubleshooting

### Common Issues

**External IPs not working:**

- Verify LoadBalancer IP pool exists: `kubectl get ciliumloadbalancerippool -n cilium`
- Check that the CIDR matches your cluster's external IP allocation
- Verify Cilium is running: `kubectl get pods -n cilium`
- Check Cilium agent logs for IP pool errors

**L2 announcements not working:**

- Verify L2 announcement policy exists: `kubectl get ciliuml2announcementpolicy -n cilium`
- Check that Cilium has L2 announcements enabled (configured in main Cilium chart)
- Verify services have external IPs or LoadBalancer type
- Check Cilium agent logs for announcement errors

**Resources not syncing:**

- Check Application status: `kubectl get application cilium-config -n argocd`
- Verify Cilium CRDs are installed: `kubectl get crd | grep cilium`
- Check that external_ip_cidr value is provided correctly

### Health Checks

- Verify resources exist: `kubectl get ciliumloadbalancerippool,ciliuml2announcementpolicy -n cilium`
- Check Application is synced: `kubectl get application cilium-config -n argocd` (should show `Synced` and `Healthy`)

## Maintenance

### Update Procedures

- Modify templates in `templates/` directory
- ArgoCD will automatically sync changes when committed to Git

### Backup Requirements

All configuration is defined as code in Git. The Cilium CRD resources can be recreated from the repository. No backups needed.

### Known Limitations

- The external IP CIDR must match the cluster's actual external IP allocation
- L2 announcements require appropriate network configuration on the physical network
- The `announce-everything` policy applies to all services (no selectors) - this may need to be more restrictive in some environments
