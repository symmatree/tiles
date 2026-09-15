# Component README Index

This document indexes the components in the tiles cluster that have README documentation, with links to it.

Not everything here has a README yet -- the mixin environments under `tanka/environments/*-mixin` are mostly a `main.jsonnet` and a vendored upstream mixin, and are listed only where one exists.

## Infrastructure Components

### ArgoCD

- **README**: [`charts/argocd/README.md`](../charts/argocd/README.md)
- **Application**: [`charts/argocd/application.yaml`](../charts/argocd/application.yaml)
- **Description**: GitOps continuous delivery tool that manages the deployment of all other components in the cluster.

### ArgoCD Applications

- **README**: [`charts/argocd-applications/README.md`](../charts/argocd-applications/README.md)
- **Application**: installed by [`charts/argocd-applications-installer/templates/application.yaml`](../charts/argocd-applications-installer/templates/application.yaml), which Terraform applies
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

### ArgoCD Applications Installer

- **README**: [`charts/argocd-applications-installer/README.md`](../charts/argocd-applications-installer/README.md)
- **Description**: One chart, one resource: the `argocd-applications` Application, applied by Terraform to bootstrap the app-of-apps.
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

### JupyterHub

- **README**: [`charts/jupyterhub/README.md`](../charts/jupyterhub/README.md)
- **Application**: [`charts/jupyterhub/application.yaml`](../charts/jupyterhub/application.yaml)
- **Description**: Always-on JupyterHub wrapping zero-to-jupyterhub-k8s, with direct SSH access to singleuser servers.
### fleet-control

- **README**: [`tanka/environments/fleet-control/README.md`](../tanka/environments/fleet-control/README.md)
- **Application**: [`tanka/environments/fleet-control/application.yaml`](../tanka/environments/fleet-control/application.yaml)
- **Description**: Ground-station control surface for the rekon10 fleet; sets up a freshly flashed card and manages the fleet inventory.
### flight-analysis

- **README**: [`tanka/environments/flight-analysis/README.md`](../tanka/environments/flight-analysis/README.md)
- **Application**: [`tanka/environments/flight-analysis/application.yaml`](../tanka/environments/flight-analysis/application.yaml)
- **Description**: Nightly CronJob running the rekon10 flight-analysis notebook over NAS flight captures.
### vio-offline

- **README**: [`tanka/environments/vio-offline/README.md`](../tanka/environments/vio-offline/README.md)
- **Application**: [`tanka/environments/vio-offline/application.yaml`](../tanka/environments/vio-offline/application.yaml)
- **Description**: Nightly VINS pose regeneration over the NAS flight captures; the estimator-half sibling of flight-analysis.
### MAVProxy (ground proxy)

- **README**: [`tanka/environments/mavproxy/README.md`](../tanka/environments/mavproxy/README.md)
- **Description**: Always-on MAVLink hub on bare-metal node acebase: ELRS backpack UDP in, NTRIP RTCM to the drone, TCP out for Mission Planner.
### NTRIP / RTKBase

- **README**: [`tanka/environments/ntrip/README.md`](../tanka/environments/ntrip/README.md)
- **Description**: GNSS base and local NTRIP caster on bare-metal node acebase. Prod only -- there is no acebase on test.
### Apprise Mixin

- **README**: [`tanka/environments/apprise-mixin/README.md`](../tanka/environments/apprise-mixin/README.md)
- **Description**: Monitoring mixin for Apprise, the notification delivery backend.
### Backpack Mixin

- **README**: [`tanka/environments/backpack-mixin/README.md`](../tanka/environments/backpack-mixin/README.md)
- **Description**: Grafana dashboard for the ELRS TX backpack's WiFi link.
## Container Images

Image sources built from this repo, deployed by the components above.

### argo-tag-watcher

- **README**: [`containers/argo-tag-watcher/README.md`](../containers/argo-tag-watcher/README.md)
- **Description**: Tiny in-cluster controller that makes Argo CD notice git changes without a manual refresh.
### mavproxy

- **README**: [`containers/mavproxy/README.md`](../containers/mavproxy/README.md)
- **Description**: amd64 image for the rekon10 always-on ground MAVLink proxy.
### rtkbase

- **README**: [`containers/rtkbase/README.md`](../containers/rtkbase/README.md)
- **Description**: amd64 image running Stefal/rtkbase under systemd for the acebase GNSS base and NTRIP caster.
## Terraform Roots

### tf/bootstrap

- **README**: [`tf/bootstrap/README.md`](../tf/bootstrap/README.md)
- **Description**: Seed-project Terraform run interactively as yourself: GCP projects, workload identity, GitHub, 1Password, Proxmox and UniFi bootstrap.
### tf/nodes

- **README**: [`tf/nodes/README.md`](../tf/nodes/README.md)
- **Description**: Cluster Terraform: Proxmox VMs, bare-metal Talos nodes, the Talos cluster itself, and the Kubernetes-facing releases (Cilium, Argo CD).
## Related Documentation

- **NFS Storage Architecture**: [`nfs-storage-architecture.md`](nfs-storage-architecture.md) - Detailed documentation on NFS storage setup and usage
- **Monitoring Mixins**: [`monitoring-mixins.md`](monitoring-mixins.md) - Information on how mixins work in this cluster
- **Secret Management**: [`secrets.md`](secrets.md) - Documentation on secret management using 1Password
