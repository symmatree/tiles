# Component index

This index summarizes what the clusters run and where to read it. **Argo CD Applications** (the app-of-apps chart) registers one Argo `Application` per file under [`charts/argocd-applications/templates/`](https://github.com/symmatree/tiles/tree/main/charts/argocd-applications/templates) (`*-application.yaml`). Those files are either **inline** Helm `Application` manifests or **symlinks** into [`charts/`](https://github.com/symmatree/tiles/tree/main/charts) or [`tanka/environments/`](https://github.com/symmatree/tiles/tree/main/tanka/environments).

Unless noted, **Application** below is always that template path (even when the symlink resolves elsewhere) so it matches what the app-of-apps chart ships.

## Bootstrap and GitOps

### Argo CD

- **Terraform**: N/A (bootstrapped manually)
- **Application**: [`charts/argocd-applications/templates/argocd-application.yaml`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/argocd-application.yaml) (symlink to [`charts/argocd/application.yaml`](https://github.com/symmatree/tiles/blob/main/charts/argocd/application.yaml))
- **README**: [`charts/argocd/README.md`](https://github.com/symmatree/tiles/blob/main/charts/argocd/README.md)
- **Description**: GitOps controller; root of the chain.

### Argo CD Applications (app-of-apps)

- **Terraform**: N/A
- **Application**: [`charts/argocd-applications/application.yaml`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/application.yaml)
- **README**: [`charts/argocd-applications/README.md`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/README.md)
- **Description**: Meta-chart whose templates render the per-component Argo `Application` resources and propagate values.

## Cluster platform

### cert-manager

- **Terraform**: [`tf/modules/k8s-cluster/k8s-cert-manager.tf`](https://github.com/symmatree/tiles/blob/main/tf/modules/k8s-cluster/k8s-cert-manager.tf)
- **Application**: [`charts/argocd-applications/templates/cert-manager-application.yaml`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/cert-manager-application.yaml)
- **README**: [`charts/cert-manager/README.md`](https://github.com/symmatree/tiles/blob/main/charts/cert-manager/README.md)
- **Description**: TLS certificates (for example Let's Encrypt via DNS01).

### Cilium

- **Terraform**: N/A (bootstrapped manually)
- **Application**: [`charts/argocd-applications/templates/cilium-application.yaml`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/cilium-application.yaml)
- **README**: [`charts/cilium/README.md`](https://github.com/symmatree/tiles/blob/main/charts/cilium/README.md)
- **Description**: CNI, kube-proxy replacement, ingress/gateway, network policy.

### Cilium Config

- **Terraform**: N/A
- **Application**: [`charts/argocd-applications/templates/cilium-config-application.yaml`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/cilium-config-application.yaml)
- **README**: [`charts/cilium-config/README.md`](https://github.com/symmatree/tiles/blob/main/charts/cilium-config/README.md)
- **Description**: Extra Cilium settings (for example cluster-specific IPAM or L2 knobs) layered after the base chart.

### external-dns

- **Terraform**: [`tf/modules/k8s-cluster/external-dns.tf`](https://github.com/symmatree/tiles/blob/main/tf/modules/k8s-cluster/external-dns.tf)
- **Application**: [`charts/argocd-applications/templates/external-dns-application.yaml`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/external-dns-application.yaml)
- **README**: [`charts/external-dns/README.md`](https://github.com/symmatree/tiles/blob/main/charts/external-dns/README.md)
- **Description**: Syncs Ingress/Service hostnames to Google Cloud DNS.

### Local Path Provisioner

- **Terraform**: N/A
- **Application**: [`charts/argocd-applications/templates/local-path-provisioner-application.yaml`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/local-path-provisioner-application.yaml)
- **README**: [`charts/argocd-applications/templates/README-local-path-provisioner.md`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/README-local-path-provisioner.md)
- **Description**: Simple local `PersistentVolume` provisioning on node disks (no top-level `charts/local-path-provisioner/` chart; lives under app-of-apps only).

### NFS CSI driver

- **Terraform**: N/A (NFS server paths for workloads are passed via Talos / cluster vars; see [`tf/nodes/cluster.tf`](https://github.com/symmatree/tiles/blob/main/tf/nodes/cluster.tf) and [`tf/modules/talos-cluster/main.tf`](https://github.com/symmatree/tiles/blob/main/tf/modules/talos-cluster/main.tf) for `cluster_nfs_path` / related inputs, not a dedicated `nfs-csi` TF file)
- **Application**: [`charts/argocd-applications/templates/nfs-csi-driver-application.yaml`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/nfs-csi-driver-application.yaml)
- **README**: [`charts/argocd-applications/templates/README-nfs-csi-driver.md`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/README-nfs-csi-driver.md)
- **Description**: CSI driver for NFS-backed storage classes.

### OnePassword Operator

- **Terraform**: N/A (bootstrapped manually)
- **Application**: [`charts/argocd-applications/templates/onepassword-application.yaml`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/onepassword-application.yaml)
- **README**: [`charts/onepassword/README.md`](https://github.com/symmatree/tiles/blob/main/charts/onepassword/README.md)
- **Description**: Syncs 1Password items into Kubernetes secrets.

### static-certs

- **Terraform**: N/A
- **Application**: [`charts/argocd-applications/templates/static-certs-application.yaml`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/static-certs-application.yaml)
- **README**: [`charts/static-certs/README.md`](https://github.com/symmatree/tiles/blob/main/charts/static-certs/README.md)
- **Description**: Long-lived or manually managed cert material used by the cluster.

## Observability stack

### Alloy

- **Terraform**: N/A
- **Application**: [`charts/argocd-applications/templates/alloy-application.yaml`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/alloy-application.yaml)
- **README**: [`charts/argocd-applications/templates/README-alloy.md`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/README-alloy.md)
- **Description**: Telemetry collector forwarding to Loki/Mimir (no `charts/alloy/` directory).

### Grafana

- **Terraform**: N/A
- **Application**: [`charts/argocd-applications/templates/grafana-application.yaml`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/grafana-application.yaml)
- **README**: [`charts/argocd-applications/templates/README-grafana.md`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/README-grafana.md)
- **Description**: Dashboards and alerting UI (upstream Grafana Helm chart sourced in the template).

### Loki

- **Terraform**: N/A (no `loki.tf` under [`tf/modules/k8s-cluster/`](https://github.com/symmatree/tiles/tree/main/tf/modules/k8s-cluster) in this repo snapshot)
- **Application**: [`charts/argocd-applications/templates/loki-application.yaml`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/loki-application.yaml)
- **README**: [`charts/argocd-applications/templates/README-loki.md`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/README-loki.md)
- **Description**: Log aggregation backed by GCS settings in the Argo Application.

### Mimir

- **Terraform**: N/A (no `mimir.tf` under [`tf/modules/k8s-cluster/`](https://github.com/symmatree/tiles/tree/main/tf/modules/k8s-cluster); [`charts/mimir/`](https://github.com/symmatree/tiles/tree/main/charts/mimir) holds webhook assets only, not an Argo `application.yaml`)
- **Application**: [`charts/argocd-applications/templates/mimir-application.yaml`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/mimir-application.yaml)
- **README**: [`charts/argocd-applications/templates/README-mimir.md`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/README-mimir.md)
- **Description**: Prometheus-compatible metrics backend (GCS-backed in template).

## Grafana / Prometheus mixins (Tanka)

Thin Argo apps that render Jsonnet mixins (dashboards/rules), not the primary workload charts.

### Argo CD mixin

- **Terraform**: N/A
- **Application**: [`charts/argocd-applications/templates/argocd-mixin-application.yaml`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/argocd-mixin-application.yaml)
- **README**: [`charts/argocd-applications/templates/README-argocd-mixin.md`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/README-argocd-mixin.md)
- **Description**: Monitoring mixin for Argo CD.

### Cilium mixin

- **Terraform**: N/A
- **Application**: [`charts/argocd-applications/templates/cilium-mixin-application.yaml`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/cilium-mixin-application.yaml)
- **README**: [`charts/argocd-applications/templates/README-cilium-mixin.md`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/README-cilium-mixin.md)
- **Description**: Monitoring mixin for Cilium.

### CoreDNS mixin

- **Terraform**: N/A
- **Application**: [`charts/argocd-applications/templates/coredns-mixin-application.yaml`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/coredns-mixin-application.yaml)
- **README**: N/A in-repo stub next to app (see [`tanka/environments/coredns-mixin/main.jsonnet`](https://github.com/symmatree/tiles/blob/main/tanka/environments/coredns-mixin/main.jsonnet))
- **Description**: Grafana dashboards for CoreDNS metrics (tanka env `coredns-mixin`).

### Kubernetes mixin

- **Terraform**: N/A
- **Application**: [`charts/argocd-applications/templates/kubernetes-mixin-application.yaml`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/kubernetes-mixin-application.yaml)
- **README**: [`charts/argocd-applications/templates/README-kubernetes-mixin.md`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/README-kubernetes-mixin.md)
- **Description**: Cluster-wide Kubernetes monitoring mixin.

### Node exporter mixin

- **Terraform**: N/A
- **Application**: [`charts/argocd-applications/templates/node-exporter-mixin-application.yaml`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/node-exporter-mixin-application.yaml)
- **README**: [`charts/argocd-applications/templates/README-node-exporter-mixin.md`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/README-node-exporter-mixin.md)
- **Description**: Node-exporter monitoring mixin.

## Data and application workloads

### Postgres operator

- **Terraform**: N/A
- **Application**: [`charts/argocd-applications/templates/postgres-operator-application.yaml`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/postgres-operator-application.yaml)
- **README**: N/A (no sibling README in templates; use upstream Zalando docs from comments in the Application if needed)
- **Description**: Zalando Postgres operator.

### Postgres operator UI

- **Terraform**: N/A
- **Application**: [`charts/argocd-applications/templates/postgres-operator-ui-application.yaml`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/postgres-operator-ui-application.yaml)
- **README**: N/A
- **Description**: UI for the Postgres operator.

### ODM

- **Terraform**: N/A
- **Application**: [`charts/argocd-applications/templates/odm-application.yaml`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/odm-application.yaml)
- **README**: [`tanka/environments/odm/README.md`](https://github.com/symmatree/tiles/blob/main/tanka/environments/odm/README.md)
- **Description**: ODM workload (tanka-rendered).

### Apprise

- **Terraform**: [`tf/modules/k8s-cluster/apprise.tf`](https://github.com/symmatree/tiles/blob/main/tf/modules/k8s-cluster/apprise.tf)
- **Application**: [`charts/argocd-applications/templates/apprise-application.yaml`](https://github.com/symmatree/tiles/blob/main/charts/argocd-applications/templates/apprise-application.yaml)
- **README**: [`tanka/environments/apprise/README.md`](https://github.com/symmatree/tiles/blob/main/tanka/environments/apprise/README.md)
- **Description**: Notification proxy (tanka env `apprise`).

## DNS (Google Cloud)

### DNS zone

- **Terraform**: [`tf/modules/k8s-cluster/dns.tf`](https://github.com/symmatree/tiles/blob/main/tf/modules/k8s-cluster/dns.tf)
- **Application**: N/A (GCP managed zone, not an Argo Application)
- **Description**: Delegated DNS for the cluster zone (paired with external-dns above).

## How READMEs are laid out

- **Symlinked** `*-application.yaml` entries usually have a **component README** under [`charts/<name>/README.md`](https://github.com/symmatree/tiles/tree/main/charts) when that chart directory exists.
- **Inline** app-of-apps templates often ship [`charts/argocd-applications/templates/README-<component>.md`](https://github.com/symmatree/tiles/tree/main/charts/argocd-applications/templates) next to the Application.
- **Tanka** workloads document under [`tanka/environments/<env>/README.md`](https://github.com/symmatree/tiles/tree/main/tanka/environments).
