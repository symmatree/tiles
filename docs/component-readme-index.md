# Component README Index

This document provides an index of all components in the tiles cluster with links to their README documentation.

## Infrastructure Components

### ArgoCD

- **README**: [`charts/argocd/README.md`](../charts/argocd/README.md)
- **Application**: [`charts/argocd/application.yaml`](../charts/argocd/application.yaml)
- **Description**: GitOps continuous delivery tool that manages the deployment of all other components in the cluster.

### ArgoCD Applications

- **README**: [`charts/argocd-applications/README.md`](../charts/argocd-applications/README.md)
- **Application**: [`charts/argocd-applications/application.yaml`](../charts/argocd-applications/application.yaml)
- **Description**: Meta-application that manages ArgoCD Application resources for all other components, propagating configuration values.

### Cilium

- **README**: [`charts/cilium/README.md`](../charts/cilium/README.md)
- **Application**: [`charts/cilium/application.yaml`](../charts/cilium/application.yaml)
- **Description**: Cloud-native networking and security platform providing CNI functionality, network policies, and observability through Hubble.

### Cilium Config

- **README**: [`charts/cilium-config/README.md`](../charts/cilium-config/README.md)
- **Application**: [`charts/cilium-config/application.yaml`](../charts/cilium-config/application.yaml)
- **Description**: Additional configuration for Cilium, creating `CiliumLoadBalancerIPPool` and `CiliumL2AnnouncementPolicy` resources.

### Local Path Provisioner

- **README**: [`charts/argocd-applications/templates/README-local-path-provisioner.md`](../charts/argocd-applications/templates/README-local-path-provisioner.md)
- **Application**: [`charts/argocd-applications/templates/local-path-provisioner-application.yaml`](../charts/argocd-applications/templates/local-path-provisioner-application.yaml)
- **Description**: Dynamic storage provisioner that creates persistent volumes using local node storage paths.

### NFS CSI Driver

- **README**: [`charts/argocd-applications/templates/README-nfs-csi-driver.md`](../charts/argocd-applications/templates/README-nfs-csi-driver.md)
- **Application**: [`charts/argocd-applications/templates/nfs-csi-driver-application.yaml`](../charts/argocd-applications/templates/nfs-csi-driver-application.yaml)
- **Description**: Critical storage infrastructure component providing NFS storage for Loki, Mimir, and ODM. See [`nfs-storage-architecture.md`](nfs-storage-architecture.md) for detailed architecture.

### DNS Zone (Google Cloud)

- **Terraform**: [`tf/modules/k8s-cluster/dns.tf`](../tf/modules/k8s-cluster/dns.tf)
- **Description**: Infrastructure-only resource. Google Cloud DNS managed zone for the cluster subdomain. No separate README needed.

## Security & Secrets

### cert-manager

- **README**: [`charts/cert-manager/README.md`](../charts/cert-manager/README.md)
- **Application**: [`charts/cert-manager/application.yaml`](../charts/cert-manager/application.yaml)
- **Terraform**: [`tf/modules/k8s-cluster/k8s-cert-manager.tf`](../tf/modules/k8s-cluster/k8s-cert-manager.tf)
- **Description**: Automated certificate management for Kubernetes, providing Let's Encrypt certificates via DNS01 challenges.

### OnePassword Operator

- **README**: [`charts/onepassword/README.md`](../charts/onepassword/README.md)
- **Application**: [`charts/onepassword/application.yaml`](../charts/onepassword/application.yaml)
- **Description**: Kubernetes operator that synchronizes secrets from 1Password vaults into Kubernetes secrets.

### static-certs

- **README**: [`charts/static-certs/README.md`](../charts/static-certs/README.md)
- **Application**: [`charts/static-certs/application.yaml`](../charts/static-certs/application.yaml)
- **Description**: Manages one-off TLS certificates for external resources (not associated with ingresses), using cert-manager for home network resources.

## DNS & Networking

### external-dns

- **README**: [`charts/external-dns/README.md`](../charts/external-dns/README.md)
- **Application**: [`charts/external-dns/application.yaml`](../charts/external-dns/application.yaml)
- **Terraform**: [`tf/modules/k8s-cluster/external-dns.tf`](../tf/modules/k8s-cluster/external-dns.tf)
- **Description**: Automatically synchronizes Kubernetes ingress and service resources with Google Cloud DNS.

## Observability Stack

### Alloy

- **README**: [`charts/argocd-applications/templates/README-alloy.md`](../charts/argocd-applications/templates/README-alloy.md)
- **Application**: [`charts/argocd-applications/templates/alloy-application.yaml`](../charts/argocd-applications/templates/alloy-application.yaml)
- **Description**: Grafana's telemetry collector that scrapes metrics and logs from cluster components and forwards them to Mimir and Loki.

### Grafana

- **README**: [`charts/argocd-applications/templates/README-grafana.md`](../charts/argocd-applications/templates/README-grafana.md)
- **Application**: [`charts/argocd-applications/templates/grafana-application.yaml`](../charts/argocd-applications/templates/grafana-application.yaml)
- **Description**: Visualization and analytics platform for metrics and logs, providing dashboards and alerting capabilities.

### Loki

- **README**: [`charts/argocd-applications/templates/README-loki.md`](../charts/argocd-applications/templates/README-loki.md)
- **Application**: [`charts/argocd-applications/templates/loki-application.yaml`](../charts/argocd-applications/templates/loki-application.yaml)
- **Description**: Log aggregation system that collects, stores, and queries logs from cluster components, using on-premises NFS storage.

### Mimir

- **README**: [`charts/argocd-applications/templates/README-mimir.md`](../charts/argocd-applications/templates/README-mimir.md)
- **Application**: [`charts/argocd-applications/templates/mimir-application.yaml`](../charts/argocd-applications/templates/mimir-application.yaml)
- **Description**: Horizontally scalable Prometheus-compatible metrics storage backend, using on-premises NFS storage.

### Monitoring Mixins

#### ArgoCD Mixin

- **README**: [`charts/argocd-applications/templates/README-argocd-mixin.md`](../charts/argocd-applications/templates/README-argocd-mixin.md)
- **Application**: [`charts/argocd-applications/templates/argocd-mixin-application.yaml`](../charts/argocd-applications/templates/argocd-mixin-application.yaml)
- **Description**: Prometheus/Grafana mixin providing dashboards and alerts for ArgoCD monitoring.

#### Cilium Mixin

- **README**: [`charts/argocd-applications/templates/README-cilium-mixin.md`](../charts/argocd-applications/templates/README-cilium-mixin.md)
- **Application**: [`charts/argocd-applications/templates/cilium-mixin-application.yaml`](../charts/argocd-applications/templates/cilium-mixin-application.yaml)
- **Description**: Prometheus/Grafana mixin providing dashboards and alerts for Cilium networking monitoring.

#### Kubernetes Mixin

- **README**: [`charts/argocd-applications/templates/README-kubernetes-mixin.md`](../charts/argocd-applications/templates/README-kubernetes-mixin.md)
- **Application**: [`charts/argocd-applications/templates/kubernetes-mixin-application.yaml`](../charts/argocd-applications/templates/kubernetes-mixin-application.yaml)
- **Description**: Prometheus/Grafana mixin providing dashboards and alerts for Kubernetes cluster monitoring.

#### Node Exporter Mixin

- **README**: [`charts/argocd-applications/templates/README-node-exporter-mixin.md`](../charts/argocd-applications/templates/README-node-exporter-mixin.md)
- **Application**: [`charts/argocd-applications/templates/node-exporter-mixin-application.yaml`](../charts/argocd-applications/templates/node-exporter-mixin-application.yaml)
- **Description**: Prometheus/Grafana mixin providing dashboards and alerts for node-level system metrics.

## Application Services

### Apprise

- **README**: [`tanka/environments/apprise/README.md`](../tanka/environments/apprise/README.md)
- **Application**: [`tanka/environments/apprise/application.yaml`](../tanka/environments/apprise/application.yaml)
- **Terraform**: [`tf/modules/k8s-cluster/apprise.tf`](../tf/modules/k8s-cluster/apprise.tf)
- **Description**: Centralized notification service providing a unified API for sending alerts and notifications to multiple channels.

### ODM (OpenDroneMap)

- **README**: [`tanka/environments/odm/README.md`](../tanka/environments/odm/README.md)
- **Application**: [`tanka/environments/odm/application.yaml`](../tanka/environments/odm/application.yaml)
- **Description**: Photogrammetry application for processing drone imagery into 3D models, point clouds, and orthomosaics.

## Related Documentation

- **NFS Storage Architecture**: [`nfs-storage-architecture.md`](nfs-storage-architecture.md) - Detailed documentation on NFS storage setup and usage
- **Monitoring Mixins**: [`monitoring-mixins.md`](monitoring-mixins.md) - Information on how mixins work in this cluster
- **Secret Management**: [`secrets.md`](secrets.md) - Documentation on secret management using 1Password
