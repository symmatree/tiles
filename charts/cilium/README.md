# Cilium

## Overview

[Cilium](https://github.com/cilium/cilium) is the cloud-native networking and security platform providing CNI (Container Network Interface) functionality for the cluster. It replaces kube-proxy and provides advanced networking features including network policies, service mesh capabilities, and observability through [Hubble](https://github.com/cilium/hubble).

Cilium is bootstrapped via CI workflow before ArgoCD (as the CNI must be installed for the cluster to function), then managed by ArgoCD through its Application resource.

## Architecture

Cilium is deployed using the [Cilium Helm chart](https://github.com/cilium/cilium/tree/main/install/kubernetes/cilium) with the following key components:

- **Cilium Agent**: Runs on each node, handles networking and security policies
- **Cilium Operator**: Manages cluster-wide operations and state
- **Hubble**: Network observability platform providing flow visibility
- **Hubble UI**: Web interface for viewing network flows and metrics

### Networking Mode

Cilium uses **direct routing mode** (`autoDirectNodeRoutes: true`) which provides better performance than overlay networking by routing traffic directly between nodes without encapsulation.

### Key Features

- **Bandwidth Manager**: Enabled with BBR (Bottleneck Bandwidth and Round-trip propagation time) TCP congestion control for optimized pod-to-pod traffic
- **L2 Announcements**: Enabled for service IP announcements on the local network
- **Network Policies**: Kubernetes NetworkPolicy and CiliumNetworkPolicy support
- **Service Mesh**: eBPF-based service mesh capabilities (not currently used)
- **Ingress Controller**: Provides ingress functionality (used by other components)

## Configuration

### Key Configuration Values

Configuration is managed through `values.yaml` and overridden via the Application's `valuesObject`:

- **Pod CIDR**: `cilium.ipv4NativeRoutingCIDR` - Set to cluster's pod CIDR for direct routing
- **Cluster Name**: `cilium.cluster.name` - Cluster identifier
- **Hubble UI Ingress**: `hubble.ui.ingress.hosts[0]` - Set to `hubble.{cluster_name}.symmatree.com`
- **Hubble TLS**: Uses cert-manager issuer for TLS certificates

### Environment-Specific Settings

- Pod CIDR is cluster-specific and set during bootstrap
- Cluster name is set during bootstrap
- Hubble UI hostname is cluster-specific

### Dependencies

- **cert-manager**: Required for Hubble UI TLS certificates
- **external-dns**: Required for Hubble UI DNS record creation

## Prerequisites

### Required Components

- **Kubernetes cluster**: With control plane nodes running (Cilium is the first component installed after cluster bootstrap)
- **CRDs**: Some CRDs may be installed before Cilium (cert-manager CRDs for TLS), but Cilium will install its own CRDs

### Required Values

- `pod_cidr`: Pod network CIDR range
- `cluster_name`: Cluster identifier

### Required Infrastructure

- Network connectivity between nodes
- Nodes with appropriate network interfaces for direct routing

## Terraform Integration

N/A - Cilium is bootstrapped via CI workflow and does not have Terraform-managed resources.

## Application Manifest

- **Application**: [`application.yaml`](application.yaml)
- **Helm Chart**: Uses the `charts/cilium` directory as a Helm chart
- **Values**: [`values.yaml`](values.yaml)
- **Namespace**: `cilium`
- **Sync Policy**: Automated with prune and self-heal enabled
- **Sync Options**:
  - `CreateNamespace=true`
  - `ServerSideApply=true`

### Bootstrap Process

Cilium is initially bootstrapped via the CI workflow (`.github/workflows/bootstrap-cluster.yaml`) which runs [`bootstrap.sh`](bootstrap.sh):

1. Creates the `cilium` namespace with privileged pod security labels
2. Runs `helm template` with cluster-specific values (pod CIDR, cluster name, Hubble UI hostname, loaded from 1Password)
3. Applies manifests via `kubectl apply --server-side`
4. Skips CRD installation (CRDs are installed separately or by Cilium itself)

After bootstrap, the `argocd-applications` chart installs the Cilium Application resource, which enables ArgoCD management. Cilium then syncs itself and becomes self-managed.

**Note**: Cilium must be installed before ArgoCD, as the cluster needs a functioning CNI for pods to start.

## Access & Endpoints

### Hubble UI

- **URL**: `https://hubble.{cluster_name}.symmatree.com`
- **Purpose**: Network flow visibility, metrics, and observability
- **TLS**: Managed by cert-manager

### API

- Cilium agent and operator expose metrics endpoints
- Hubble exposes gRPC and HTTP APIs for flow data

## Monitoring & Observability

### Metrics

- **Cilium Agent**: Exposes Prometheus metrics on each node
- **Cilium Operator**: Exposes Prometheus metrics
- **Hubble**: Exposes metrics for network flows and observability
- **ServiceMonitors**: TODO: Document ServiceMonitor configuration

### Dashboards

Grafana dashboards from the [Cilium mixin](../argocd-applications/templates/README-cilium-mixin.md):

**Working dashboards:**

- **Cilium Network**: Displays network metrics and statistics
- **Cilium Operator**: Displays operator metrics
- **Hubble / Network Overview (Namespace)**: Network flow overview by namespace
- **Hubble L7 HTTP Metrics by Workload**: HTTP-level metrics
- **Hubble Metrics and Monitoring**: General Hubble observability metrics

**Broken or not useful:**

- **Hubble / DNS Overview (Namespace)**: Not functional or provides no useful data

### Alerts

Prometheus alerts are defined by the [Cilium mixin](../argocd-applications/templates/README-cilium-mixin.md). Alerts are deployed as PrometheusRule resources in the `cilium` namespace, discovered by Alloy, and pushed to Mimir's Ruler for evaluation.

- TODO: Alerts are missing - need to configure PrometheusRules for Cilium

### Logs

View component logs:

```bash
# Cilium agent logs (on each node)
kubectl logs -n cilium -l k8s-app=cilium

# Cilium operator logs
kubectl logs -n cilium -l name=cilium-operator

# Hubble relay logs
kubectl logs -n cilium -l app.kubernetes.io/name=hubble-relay

# Hubble UI logs
kubectl logs -n cilium -l app.kubernetes.io/name=hubble-ui
```

## Troubleshooting

### Common Issues

**Pods cannot start / network not working:**

- Verify Cilium agent pods are running on all nodes: `kubectl get pods -n cilium -l k8s-app=cilium`
- Check Cilium agent logs for errors (see Logs section above)
- Verify pod CIDR matches cluster configuration: `kubectl get configmap -n cilium cilium-config -o yaml`
- Check node connectivity: `cilium status` (if cilium CLI available)

**Hubble UI not accessible:**

- Verify ingress is created: `kubectl get ingress -n cilium`
- Check certificate status: `kubectl get certificate -n cilium`
- Verify external-dns created DNS record
- Check Hubble UI pod logs (see Logs section above)
- Verify Hubble UI pods are running: `kubectl get pods -n cilium -l app.kubernetes.io/name=hubble-ui`

**Network policies not working:**

- Verify CiliumNetworkPolicy CRD is installed: `kubectl get crd ciliumnetworkpolicies.cilium.io`
- Check Cilium agent logs for policy enforcement errors
- Verify policies are correctly formatted

### Health Checks

- Verify all Cilium pods are running: `kubectl get pods -n cilium`
- Check Cilium agent status on nodes: TODO: Document cilium status command or health check endpoint
- Verify Hubble is running: `kubectl get pods -n cilium -l app.kubernetes.io/name=hubble-relay`

## Maintenance

### Update Procedures

- TODO: Document update procedure (Helm chart version updates, Cilium version updates)

### Backup Requirements

All configuration is defined as code in Git. The Cilium configuration can be recreated from the repository. No backups needed.

### Known Limitations

- Some Linux capabilities are disabled due to Talos Linux restrictions (notably `SYS_MODULE`)
- Cilium must be installed before ArgoCD (cluster requires CNI to function)
- Hubble DNS Overview dashboard is not functional

## Talos-Specific Configuration

Cilium is configured to work with Talos Linux, which has some restrictions:

- **SYS_MODULE capability disabled**: Required for loading kernel modules, but Talos doesn't allow this
- **Direct routing mode**: Used instead of overlay networking for better performance and compatibility
- **k8sServiceHost/Port**: Set to `localhost:7445` for Talos API access

These settings are documented in `values.yaml` with comments explaining Talos-specific requirements.
