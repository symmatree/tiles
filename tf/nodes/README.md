# tf/nodes

Terraform configuration for managing cluster nodes, including VMs, bare metal nodes, and associated infrastructure.

## Prerequisites

* Terraform **1.8+** (`required_version` in `versions.tf`; cross-type `moved` for Proxmox refactors)
* 1Password vault with required secrets (see `docs/secrets.md`)
* GCP authentication configured (both direct and application-default)
* Access to Proxmox, UniFi, Synology, and Cloudflare APIs

## Required Environment Variables

The following environment variables must be set before running Terraform:

### 1Password Service Account Token

Required for accessing secrets from 1Password:

```bash
export TF_VAR_onepassword_sa_token=$(op read op://tiles-secrets/tiles-onepassword-sa/credential)
```

### UniFi Controller Credentials

Required for managing UniFi network resources:

```bash
export UNIFI_USERNAME=$(op read op://tiles-secrets/morpheus-terraform/username)
export UNIFI_PASSWORD=$(op read op://tiles-secrets/morpheus-terraform/password)
```

### Synology NAS Credentials

Required for managing Synology resources:

```bash
export SYNOLOGY_USER=$(op read op://tiles-secrets/raconteur-login/username)
export SYNOLOGY_PASSWORD=$(op read op://tiles-secrets/raconteur-login/password)
# Optional: override the host from terraform.tfvars
# export SYNOLOGY_HOST="https://raconteur.ad.local.symmatree.com:5001"
```

### Proxmox Root Credentials

Required for bind mounts in Proxmox containers (e.g., Alloy monitoring containers):

```bash
export TF_VAR_proxmox_root_password=$(op read op://tiles-secrets/proxmox-root/password)
```

## Usage

**IMPORTANT**: You MUST select a workspace (`test` or `prod`) before running Terraform. Running in the default workspace is dangerous and not supported.

```bash
cd tf/nodes
eval $(op signin)

# Set required environment variables
export TF_VAR_onepassword_sa_token=$(op read op://tiles-secrets/tiles-onepassword-sa/credential)
export UNIFI_USERNAME=$(op read op://tiles-secrets/morpheus-terraform/username)
export UNIFI_PASSWORD=$(op read op://tiles-secrets/morpheus-terraform/password)
export SYNOLOGY_USER=$(op read op://tiles-secrets/raconteur-login/username)
export SYNOLOGY_PASSWORD=$(op read op://tiles-secrets/raconteur-login/password)
export TF_VAR_proxmox_root_password=$(op read op://tiles-secrets/proxmox-root/password)

# Select workspace (test or prod)
terraform workspace select test  # or 'prod' for production

# Run plan with the appropriate tfvars file
terraform plan -var-file=test.tfvars  # or 'prod.tfvars' for production
```

## Workspaces

This configuration supports two workspaces:
- **test**: For the test cluster (`tiles-test`)
- **prod**: For the production cluster (`tiles`)

Each workspace has its own `.tfvars` file (`test.tfvars` or `prod.tfvars`) that must be specified with `-var-file` when running `terraform plan` or `terraform apply`. The workspace must be selected before running any Terraform commands.

## Edge Alloy (Synology + Proxmox)

Host-level Grafana Alloy (Raconteur NAS and Proxmox node LXCs) is controlled by **`deploy_synology_alloy`** and **`deploy_proxmox_alloy`** in the tfvars file. Both are **`true`** in **`prod.tfvars`** and **`false`** in **`test.tfvars`**. Apply from **`prod`** workspace with **`-var-file=prod.tfvars`** after merging config changes. See [`docs/synology-monitoring.md`](../../docs/synology-monitoring.md) and [`docs/proxmox-monitoring.md`](../../docs/proxmox-monitoring.md).

## In-cluster bootstrap (`k8s-bootstrap.tf`)

Some things have to be in the cluster before Argo CD's app-of-apps tree can
render, and CRDs are the main one: Argo CD cannot diff resources whose types it
has not seen yet, and the CRD blobs are large enough to be unpleasant for it to
carry. `k8s-bootstrap.tf` installs them as `helm_release` resources that depend
on `module.cluster`. This is the only place cluster CRDs are installed; the
there is no bootstrap workflow left to have one.

This works because **`helm_release` does not contact the API server during
plan** -- the provider only dry-runs against the cluster when the `manifest`
experiment is enabled, which this configuration deliberately does not enable. A
plan therefore succeeds against a cluster that does not exist yet, and ordinary
graph ordering is sufficient. (Enabling the experiment breaks plan with
`cluster was unreachable at create time`.) This is the opposite of
`kubernetes_manifest`, which per the provider docs "requires API access during
planning time ... and thus cannot be created in the same apply operation".

The tradeoff: a plan shows no rendered-manifest diff for a release. Chart
content is reviewed through the committed `charts/*/rendered.yaml` files
instead.

The `helm` provider is pointed at `module.cluster.bootstrap_ip`, not
`control_plane_vip`, because the VIP does not answer until Cilium is running --
the same substitution the old bootstrap workflow made on the kubeconfig.

Also here: the `onepassword` namespace and the 1Password operator's own two
secrets. Those cannot come from an `OnePasswordItem` -- they are what the
operator needs before it can serve one -- and `charts/argocd/bootstrap.sh`
applies `OnePasswordItem` CRs, so they must exist before Argo CD does. Terraform
is the namespace's only writer; the `onepassword` Application sets no
`CreateNamespace` or `managedNamespaceMetadata`.

Currently installed here:

| Release | Source | Replaces |
|---|---|---|
| `prometheus-operator-crds` | upstream `prometheus-community/prometheus-operator-crds` chart 24.0.2 (appVersion v0.86.2) | six `monitoring.coreos.com` CRDs |
| `helm_release.crds["argo-cd-crds"]` | generated, `oci://ghcr.io/symmatree/tiles/charts` | Application, ApplicationSet, AppProject |
| `helm_release.crds["cert-manager-crds"]` | generated | cert-manager CRDs |
| `helm_release.crds["trust-manager-crds"]` | generated | Bundle |
| `helm_release.crds["gateway-api-crds"]` | generated | Gateway API standard channel |
| `helm_release.crds["onepassword-crds"]` | generated | OnePasswordItem |
| `helm_release.crds["external-snapshotter-crds"]` | generated | VolumeSnapshot types |

One deliberate difference from the URLs this replaces: the chart's
`AlertmanagerConfig` CRD serves only `v1alpha1`, where the
`prometheus-operator-crd-full` YAML also served `v1beta1`. Nothing in this
cluster reads `v1beta1` -- see the comment in `k8s-bootstrap.tf`.

The generated charts are built from upstream CRD YAML by
`ci-tools/crd-charts/build.py` and pushed to GHCR by the `publish-crd-charts`
workflow. Third-party CRD YAML is never committed to this repo -- it is fetched
at build time and packaged. Where upstream publishes a usable CRD-only chart
(`prometheus-operator-crds`), that is installed directly instead.

## Rebuilds

`taint-vms` taints these releases along with the VMs. Nothing binds a release's
lifetime to the cluster it was installed into, so a rebuild would otherwise
bring up a cluster with no CRDs while state still believes they are installed.

## Cilium (`k8s-cilium.tf`)

Terraform installs the local `charts/cilium` umbrella with the same values
`charts/cilium/application.yaml` feeds Argo CD, so both render identical output.
Terraform is the only writer: that Application has no `automated` sync, so Argo
CD renders, diffs and reports drift on the CNI without correcting it, and
syncing it is a manual action.

The `cilium` subchart is not committed, so `nodes-plan-apply` runs
`.github/actions/helm-setup` to vendor it before Terraform loads the chart.

## Argo CD (`k8s-argocd.tf`)

Terraform installs the local `charts/argocd` umbrella with the same value layers
`charts/argocd/application.yaml` feeds Argo CD, so the two render identical
output. Terraform is the only writer: that Application has no `automated` sync,
so Argo CD renders, diffs and reports drift on itself without correcting it, and
syncing is manual. It owns no namespace metadata either -- Terraform creates the
`argocd` namespace, which must exist before the release goes into it.

`targetRevision` comes from `module.cluster.target_revision` rather than being
recomputed here, so the value Terraform passes is the one written to
misc-config.

The root app-of-apps Application is installed here too, from
`charts/app-of-apps`, and Argo CD's initial admin password is read from the
Secret it generates and written into the `argocd-{cluster}-admin` 1Password item
as a full login, so the browser extension still offers it.

## Which CRDs are *not* here

A CRD whose only consumers are inside the Argo CD application that ships it is
left to that application, and is not installed by Terraform: the alloy-operator
`Alloy` CRD (via `k8s-monitoring`), the rollout-operator CRDs (via
`mimir-distributed`), the `acid.zalan.do` CRDs (via `postgres-operator`), and
`DNSEndpoint` (via `external-dns`). Pulling those out would separate the CRD's
lifecycle from the custom resources that carry finalizers, which needs a
teardown strategy -- reaping the instances before the operator goes away -- that
these upstream charts do not give us a clean way to express.
