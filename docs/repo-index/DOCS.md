# tiles -- Documentation Index

Generated 2026-07-05. Summaries reflect the docs AS OF this date; verify before relying.

## What this repo is

`tiles` is a GitOps-managed home Kubernetes infrastructure repo. It provisions two Talos Linux clusters
(`tiles` and `tiles-test`) on Proxmox VMs using Terraform, then deploys all workloads via ArgoCD and
Helm (the app-of-apps pattern). A `fables/` git submodule holds the published knowledge-base pages;
the repo also contains Tanka/Jsonnet environments for drone-related services and custom container builds.

---

## Root

| Path | One-line summary | Link |
|------|-----------------|------|
| README.md | Network range allocations, cluster recreation procedures, and talosconfig usage guide | [README.md](https://github.com/symmatree/tiles/blob/main/README.md) |

---

## docs/ -- Core documentation

### Overview and navigation

| Path | One-line summary | Link |
|------|-----------------|------|
| docs/index.md | Navigational index of all docs/ files with one-paragraph summaries per document | [docs/index.md](https://github.com/symmatree/tiles/blob/main/docs/index.md) |
| docs/overview.md | Motivation, architecture philosophy, primary purposes of the cluster, and cold-start initialization procedure | [docs/overview.md](https://github.com/symmatree/tiles/blob/main/docs/overview.md) |
| docs/components.md | Index of all deployed cluster components with links to Terraform, ArgoCD Application manifests, and per-component READMEs | [docs/components.md](https://github.com/symmatree/tiles/blob/main/docs/components.md) |
| docs/component-readme-index.md | Alternate component index organized by category with links to component README files | [docs/component-readme-index.md](https://github.com/symmatree/tiles/blob/main/docs/component-readme-index.md) |
| docs/todo.md | Backlog of planned features and improvements (OIDC, LGTM stack, Grafana auth, workload identity, etc.) | [docs/todo.md](https://github.com/symmatree/tiles/blob/main/docs/todo.md) |

### Infrastructure management

| Path | One-line summary | Link |
|------|-----------------|------|
| docs/environment-strategy.md | Tag-based deployment workflow for managing test and production Terraform environments in parallel | [docs/environment-strategy.md](https://github.com/symmatree/tiles/blob/main/docs/environment-strategy.md) |
| docs/config-propagation.md | How Terraform outputs flow through 1Password and the bootstrap process into ArgoCD app-of-apps Helm values | [docs/config-propagation.md](https://github.com/symmatree/tiles/blob/main/docs/config-propagation.md) |
| docs/bare-metal-nodes.md | Bare-metal Talos worker provisioning (AMD/Intel schematics, UniFi, add/remove/reinstall, USB ISO) | [docs/bare-metal-nodes.md](https://github.com/symmatree/tiles/blob/main/docs/bare-metal-nodes.md) |
| docs/talos.md | Talos Linux image factory, installer URL shape, ISO download, and upgrade procedures | [docs/talos.md](https://github.com/symmatree/tiles/blob/main/docs/talos.md) |
| docs/api-versions-strategy.md | Strategy for version-controlling cluster API versions to enable accurate Helm templating in CI without cluster access | [docs/api-versions-strategy.md](https://github.com/symmatree/tiles/blob/main/docs/api-versions-strategy.md) |

### Networking

| Path | One-line summary | Link |
|------|-----------------|------|
| docs/cluster-network.md | Cluster network architecture: IP ranges, CIDR allocations, Cilium config, and sources of truth for network values | [docs/cluster-network.md](https://github.com/symmatree/tiles/blob/main/docs/cluster-network.md) |

### Storage

| Path | One-line summary | Link |
|------|-----------------|------|
| docs/nfs-storage-architecture.md | NFS CSI driver per-PVC directory layout, Synology export path requirements, and cluster-to-NAS path mapping | [docs/nfs-storage-architecture.md](https://github.com/symmatree/tiles/blob/main/docs/nfs-storage-architecture.md) |

### Security and secrets

| Path | One-line summary | Link |
|------|-----------------|------|
| docs/secrets.md | 1Password vault layout, Terraform-generated vs. manually created secrets, and talosconfig retrieval | [docs/secrets.md](https://github.com/symmatree/tiles/blob/main/docs/secrets.md) |
| docs/gcp-enterprise-setup.md | Four GCP projects created by bootstrap (tiles-id, tiles-kms, tiles-tf-state, tiles-main) and their purposes | [docs/gcp-enterprise-setup.md](https://github.com/symmatree/tiles/blob/main/docs/gcp-enterprise-setup.md) |

### Developer operations

| Path | One-line summary | Link |
|------|-----------------|------|
| docs/dev-setup.md | Quick-start commands for retrieving kubeconfig and talosconfig from 1Password for local cluster access | [docs/dev-setup.md](https://github.com/symmatree/tiles/blob/main/docs/dev-setup.md) |
| docs/ci-principles.md | CI assertiveness principle: conditionals about environment state are errors; tools must be installed or fail explicitly | [docs/ci-principles.md](https://github.com/symmatree/tiles/blob/main/docs/ci-principles.md) |
| docs/caching-strategy.md | GitHub Actions caching using date-based invalidation plus lock-file content keys to keep CI fast and fresh | [docs/caching-strategy.md](https://github.com/symmatree/tiles/blob/main/docs/caching-strategy.md) |
| docs/oom-troubleshooting.md | How to identify OOM-killed pods from Talos logs using cgroup paths and kubectl resource inspection | [docs/oom-troubleshooting.md](https://github.com/symmatree/tiles/blob/main/docs/oom-troubleshooting.md) |

### Monitoring and observability

| Path | One-line summary | Link |
|------|-----------------|------|
| docs/mimir.md | Grafana Mimir metrics backend: tenancy (X-Scope-OrgID), per-tenant limits, self-monitoring, and cardinality queries | [docs/mimir.md](https://github.com/symmatree/tiles/blob/main/docs/mimir.md) |
| docs/synology-monitoring.md | Grafana Alloy on Synology NAS (Raconteur): OTLP to both clusters, Mimir/Loki labels, verification queries | [docs/synology-monitoring.md](https://github.com/symmatree/tiles/blob/main/docs/synology-monitoring.md) |
| docs/proxmox-monitoring.md | Grafana Alloy in Proxmox LXC per node: cluster="bond" metrics/logs, Terraform flags, Mimir/Loki debugging notes | [docs/proxmox-monitoring.md](https://github.com/symmatree/tiles/blob/main/docs/proxmox-monitoring.md) |
| docs/monitoring-mixins.md | Approach for collecting and installing Prometheus monitoring mixins via Tanka plugin in ArgoCD | [docs/monitoring-mixins.md](https://github.com/symmatree/tiles/blob/main/docs/monitoring-mixins.md) |

---

## charts/ -- Helm chart READMEs

### Top-level chart READMEs

| Path | One-line summary | Link |
|------|-----------------|------|
| charts/argocd-applications/README.md | App-of-apps chart that deploys all ArgoCD Applications and propagates Terraform config values cluster-wide | [charts/argocd-applications/README.md](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/README.md) |
| charts/argocd/README.md | ArgoCD GitOps controller: bootstrap, self-management, and monitoring via argocd-mixin | [charts/argocd/README.md](https://github.com/symmatree/tiles/blob/main/charts/argocd/README.md) |
| charts/cert-manager/README.md | cert-manager with trust-manager: Let's Encrypt TLS automation and CA bundle distribution | [charts/cert-manager/README.md](https://github.com/symmatree/tiles/blob/main/charts/cert-manager/README.md) |
| charts/cilium/README.md | Cilium CNI replacing kube-proxy: network policies, L2 LoadBalancer IPAM, Hubble observability | [charts/cilium/README.md](https://github.com/symmatree/tiles/blob/main/charts/cilium/README.md) |
| charts/cilium-config/README.md | Cilium CRDs for external IP pools and L2 announcement policies, kept separate to avoid CRD bootstrapping race conditions | [charts/cilium-config/README.md](https://github.com/symmatree/tiles/blob/main/charts/cilium-config/README.md) |
| charts/external-dns/README.md | external-dns syncing Kubernetes ingress/service resources to Google Cloud DNS A/AAAA records | [charts/external-dns/README.md](https://github.com/symmatree/tiles/blob/main/charts/external-dns/README.md) |
| charts/jupyterhub/README.md | JupyterHub with Google OAuth and direct SSH access to singleuser pods | [charts/jupyterhub/README.md](https://github.com/symmatree/tiles/blob/main/charts/jupyterhub/README.md) |
| charts/mimir/webhook/README.md | Forked docker-apprise-webhook container for Mimir alert routing to Apprise | [charts/mimir/webhook/README.md](https://github.com/symmatree/tiles/blob/main/charts/mimir/webhook/README.md) |
| charts/onepassword/README.md | 1Password Operator: Connect API/Sync + operator to sync vault items into Kubernetes secrets via OnePasswordItem CRDs | [charts/onepassword/README.md](https://github.com/symmatree/tiles/blob/main/charts/onepassword/README.md) |
| charts/static-certs/README.md | cert-manager Certificate resources for external home-network hosts that need Let's Encrypt TLS but run outside the cluster | [charts/static-certs/README.md](https://github.com/symmatree/tiles/blob/main/charts/static-certs/README.md) |

### charts/argocd-applications/templates/ -- per-application READMEs

| Path | One-line summary | Link |
|------|-----------------|------|
| charts/argocd-applications/templates/README-alloy.md | Grafana Alloy via k8s-monitoring Helm chart: cluster metrics and logs forwarded to Mimir and Loki | [charts/argocd-applications/templates/README-alloy.md](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/README-alloy.md) |
| charts/argocd-applications/templates/README-argocd-mixin.md | ArgoCD Prometheus mixin dashboards and alerts (see charts/argocd/README.md for detail) | [charts/argocd-applications/templates/README-argocd-mixin.md](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/README-argocd-mixin.md) |
| charts/argocd-applications/templates/README-cilium-mixin.md | Cilium Prometheus mixin dashboards and alerts (see charts/cilium/README.md for detail) | [charts/argocd-applications/templates/README-cilium-mixin.md](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/README-cilium-mixin.md) |
| charts/argocd-applications/templates/README-grafana.md | Grafana visualization platform: dashboards, alerting, and LGTM stack integration | [charts/argocd-applications/templates/README-grafana.md](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/README-grafana.md) |
| charts/argocd-applications/templates/README-kubernetes-mixin.md | Kubernetes Prometheus mixin dashboards and alerts (see README-grafana.md for detail) | [charts/argocd-applications/templates/README-kubernetes-mixin.md](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/README-kubernetes-mixin.md) |
| charts/argocd-applications/templates/README-local-path-provisioner.md | Local Path Provisioner: dynamic PV provisioning from node-local storage paths | [charts/argocd-applications/templates/README-local-path-provisioner.md](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/README-local-path-provisioner.md) |
| charts/argocd-applications/templates/README-loki.md | Loki log aggregation: centralized log storage and querying as part of the LGTM stack | [charts/argocd-applications/templates/README-loki.md](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/README-loki.md) |
| charts/argocd-applications/templates/README-mimir.md | Mimir Helm chart deployment notes and key configuration decisions | [charts/argocd-applications/templates/README-mimir.md](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/README-mimir.md) |
| charts/argocd-applications/templates/README-nfs-csi-driver.md | NFS CSI Driver: Kubernetes PV/PVC support for NFS shares with RWO and RWX access modes | [charts/argocd-applications/templates/README-nfs-csi-driver.md](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/README-nfs-csi-driver.md) |
| charts/argocd-applications/templates/README-node-exporter-mixin.md | Node Exporter Prometheus mixin dashboards and alerts (see README-grafana.md for detail) | [charts/argocd-applications/templates/README-node-exporter-mixin.md](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/README-node-exporter-mixin.md) |

---

## containers/ -- Custom container images

| Path | One-line summary | Link |
|------|-----------------|------|
| containers/mavproxy/README.md | Headless MAVProxy amd64 image: ELRS UDP in, NTRIP corrections, TCP fan-out to Mission Planner | [containers/mavproxy/README.md](https://github.com/symmatree/tiles/blob/main/containers/mavproxy/README.md) |
| containers/rtkbase/README.md | RTKBase amd64 image running Stefal/rtkbase under systemd for GNSS base and NTRIP caster on acebase node | [containers/rtkbase/README.md](https://github.com/symmatree/tiles/blob/main/containers/rtkbase/README.md) |

---

## tanka/environments/ -- Tanka/Jsonnet workload environments

| Path | One-line summary | Link |
|------|-----------------|------|
| tanka/environments/apprise/README.md | Apprise notification routing service: two-tier delivery (Slack urgent + email digest) via a single API endpoint | [tanka/environments/apprise/README.md](https://github.com/symmatree/tiles/blob/main/tanka/environments/apprise/README.md) |
| tanka/environments/flight-analysis/README.md | Nightly CronJob rendering ArduPilot flight logs to .ipynb/.pdf using the flight-analysis Jupyter notebook | [tanka/environments/flight-analysis/README.md](https://github.com/symmatree/tiles/blob/main/tanka/environments/flight-analysis/README.md) |
| tanka/environments/mavproxy/README.md | Always-on MAVLink hub on acebase bare-metal node: ELRS in, NTRIP RTCM to drone, TCP out for Mission Planner | [tanka/environments/mavproxy/README.md](https://github.com/symmatree/tiles/blob/main/tanka/environments/mavproxy/README.md) |
| tanka/environments/ntrip/README.md | GNSS base and local NTRIP caster on acebase bare-metal node (prod only) | [tanka/environments/ntrip/README.md](https://github.com/symmatree/tiles/blob/main/tanka/environments/ntrip/README.md) |
| tanka/environments/odm/README.md | OpenDroneMap (WebODM) photogrammetry workload for processing drone imagery into 3D models and orthomosaics | [tanka/environments/odm/README.md](https://github.com/symmatree/tiles/blob/main/tanka/environments/odm/README.md) |

---

## tf/ -- Terraform module READMEs

| Path | One-line summary | Link |
|------|-----------------|------|
| tf/bootstrap/README.md | Bootstrap Terraform run interactively with elevated privileges: 1Password vault, GitHub repos, service accounts | [tf/bootstrap/README.md](https://github.com/symmatree/tiles/blob/main/tf/bootstrap/README.md) |
| tf/nodes/README.md | Node Terraform: VM and bare-metal provisioning for tiles and tiles-test clusters, prerequisites and workflow | [tf/nodes/README.md](https://github.com/symmatree/tiles/blob/main/tf/nodes/README.md) |
