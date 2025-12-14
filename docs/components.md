# Component Index

This document provides an index of all software components deployed in the tiles cluster. Each component entry includes links to its Terraform configuration (if applicable), Application manifest, README documentation, and a brief description.

## Infrastructure Components

### ArgoCD

- **Terraform**: N/A (bootstrapped manually)
- **Application**: [`charts/argocd/application.yaml`](../charts/argocd/application.yaml)
- **README**: [`charts/argocd/README.md`](../charts/argocd/README.md)
- **Description**: GitOps continuous delivery tool that manages the deployment of all other components in the cluster. Provides declarative application management and synchronization.

### ArgoCD Applications

- **Terraform**: N/A
- **Application**: [`charts/argocd-applications/application.yaml`](../charts/argocd-applications/application.yaml)
- **README**: [`charts/argocd-applications/README.md`](../charts/argocd-applications/README.md)
- **Description**: Meta-application that manages the ArgoCD Application resources for all other components, propagating configuration values from Terraform outputs.

### Cilium

- **Terraform**: N/A (bootstrapped manually)
- **Application**: [`charts/cilium/application.yaml`](../charts/cilium/application.yaml)
- **README**: [`charts/cilium/README.md`](../charts/cilium/README.md)
- **Description**: Cloud-native networking and security platform providing CNI (Container Network Interface) functionality, network policies, and observability through Hubble.

### Cilium Config

- **Terraform**: N/A
- **Application**: [`charts/cilium-config/application.yaml`](../charts/cilium-config/application.yaml)
- **README**: [`charts/cilium-config/README.md`](../charts/cilium-config/README.md)
- **Description**: Additional configuration for Cilium, including external IP CIDR settings and other cluster-specific networking parameters.

### Local Path Provisioner

- **Terraform**: N/A
- **Application**: [`charts/local-path-provisioner/application.yaml`](../charts/local-path-provisioner/application.yaml)
- **README**: [`charts/local-path-provisioner/README.md`](../charts/local-path-provisioner/README.md)
- **Description**: Dynamic storage provisioner that creates persistent volumes using local node storage paths, providing simple local storage for workloads that don't require shared storage.

## Security & Secrets

### cert-manager

- **Terraform**: [`tf/modules/k8s-cluster/k8s-cert-manager.tf`](../tf/modules/k8s-cluster/k8s-cert-manager.tf)
- **Application**: [`charts/cert-manager/application.yaml`](../charts/cert-manager/application.yaml)
- **README**: [`charts/cert-manager/README.md`](../charts/cert-manager/README.md)
- **Description**: Automated certificate management for Kubernetes, providing Let's Encrypt certificates via DNS01 challenges using Google Cloud DNS service accounts.

### OnePassword Operator

- **Terraform**: N/A (bootstrapped manually)
- **Application**: [`charts/onepassword/application.yaml`](../charts/onepassword/application.yaml)
- **README**: [`charts/onepassword/README.md`](../charts/onepassword/README.md)
- **Description**: Kubernetes operator that synchronizes secrets from 1Password vaults into Kubernetes secrets, enabling secure secret management without storing credentials in Git.

## DNS & Networking

### external-dns

- **Terraform**: [`tf/modules/k8s-cluster/external-dns.tf`](../tf/modules/k8s-cluster/external-dns.tf)
- **Application**: [`charts/external-dns/application.yaml`](../charts/external-dns/application.yaml)
- **README**: [`charts/external-dns/README.md`](../charts/external-dns/README.md)
- **Description**: Automatically synchronizes Kubernetes ingress and service resources with Google Cloud DNS, managing DNS records for cluster services.

### DNS Zone (Google Cloud)

- **Terraform**: [`tf/modules/k8s-cluster/dns.tf`](../tf/modules/k8s-cluster/dns.tf)
- **Application**: N/A (infrastructure resource)
- **Description**: Google Cloud DNS managed zone for the cluster subdomain, with NS record delegation configured in Cloudflare parent zone.

## Observability Stack

### Alloy

- **Terraform**: N/A
- **Application**: [`charts/alloy/application.yaml`](../charts/alloy/application.yaml)
- **README**: [`charts/alloy/README.md`](../charts/alloy/README.md)
- **Description**: Grafana's open-source telemetry collector that scrapes metrics and logs from cluster components and forwards them to Mimir and Loki respectively.

### Grafana

- **Terraform**: N/A
- **Application**: [`charts/grafana/application.yaml`](../charts/grafana/application.yaml)
- **README**: [`charts/grafana/README.md`](../charts/grafana/README.md)
- **Description**: Visualization and analytics platform for metrics and logs, providing dashboards and alerting capabilities for the LGTM (Loki/Grafana/Tempo/Mimir) observability stack.

### Loki

- **Terraform**: [`tf/modules/k8s-cluster/loki.tf`](../tf/modules/k8s-cluster/loki.tf)
- **Application**: [`charts/loki/application.yaml`](../charts/loki/application.yaml)
- **README**: [`charts/loki/README.md`](../charts/loki/README.md)
- **Description**: Horizontally scalable log aggregation system that stores logs in Google Cloud Storage buckets with encryption, providing centralized log storage and querying.

### Mimir

- **Terraform**: [`tf/modules/k8s-cluster/mimir.tf`](../tf/modules/k8s-cluster/mimir.tf)
- **Application**: [`charts/mimir/application.yaml`](../charts/mimir/application.yaml)
- **README**: [`charts/mimir/README.md`](../charts/mimir/README.md)
- **Description**: Horizontally scalable, highly available Prometheus-compatible metrics storage backend, storing metrics data in Google Cloud Storage buckets with encryption and versioning.

## Application Services

### Apprise

- **Terraform**: [`tf/modules/k8s-cluster/apprise.tf`](../tf/modules/k8s-cluster/apprise.tf)
- **Application**: [`tanka/environments/apprise/application.yaml`](../tanka/environments/apprise/application.yaml)
- **README**: [`tanka/environments/apprise/README.md`](../tanka/environments/apprise/README.md)
- **Description**: Centralized notification service that provides a unified API for sending alerts and notifications to multiple channels (email, Slack, Discord, etc.) from any system component.

## Component Documentation

Each component should have a README.md file located next to its application.yaml file (or in the same directory structure) that provides detailed documentation about:

- Component purpose and architecture
- Configuration options
- Dependencies and prerequisites
- Troubleshooting guides
- Maintenance procedures

The README files are linked from this index and referenced in comments within the relevant Terraform files.
