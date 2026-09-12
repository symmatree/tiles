# Cluster bootstrap resources installed by Terraform directly into the cluster,
# after (and depending on) the Talos cluster itself.
#
# Why this can work at all: helm_release never contacts the API server during
# plan. The provider's ModifyPlan only dry-runs against the cluster when the
# "manifest" experiment is enabled, which we deliberately leave off -- so a plan
# succeeds even when the cluster does not exist yet, and the ordinary
# depends_on/graph edge is enough. (Enabling that experiment breaks plan with
# "cluster was unreachable at create time", so do not turn it on.) This is
# unlike kubernetes_manifest, which the hashicorp/kubernetes docs state
# "requires API access during planning time ... and thus cannot be created in
# the same apply operation".
#
# The cost of leaving the experiment off is that a plan shows no rendered-manifest
# diff for a release. Chart content review happens through the committed
# charts/*/rendered.yaml files instead (see build.sh).

provider "helm" {
  kubernetes = {
    # The kubeconfig Talos issues points at control_plane_vip, which does not
    # answer until Cilium is up -- so during a cold bootstrap we would be
    # talking to an address that only exists once something we have not
    # installed yet is running. Target the first control plane node directly;
    # the API server certificate covers it (the bootstrap-cluster workflow has
    # rewritten the kubeconfig this way since before Terraform did any of this).
    host = "https://${module.cluster.bootstrap_ip}:6443"
    # base64decode is required: the talos provider hands these back exactly as a
    # kubeconfig stores them, base64-encoded (talos_cluster_kubeconfig_resource.go
    # wraps each in bytesToBase64). The helm provider wants raw PEM, and without
    # the decode it fails at apply with "Kubernetes cluster unreachable: unable to
    # load root certificates: unable to parse bytes as PEM block".
    cluster_ca_certificate = base64decode(module.cluster.kubernetes_client_configuration.ca_certificate)
    client_certificate     = base64decode(module.cluster.kubernetes_client_configuration.client_certificate)
    client_key             = base64decode(module.cluster.kubernetes_client_configuration.client_key)
  }
}

# Prometheus Operator CRDs.
#
# These are the CRDs that charts/install-crds.sh used to apply as six raw YAML
# URLs. CRDs stay out of Argo CD (it does not diff resources whose types it has
# not seen, and the blobs are large), so something has to install them ahead of
# the app-of-apps tree: that something is now Terraform.
#
# Upstream publishes a CRD-only chart at the same appVersion, so this set needs
# no repackaging on our side. Its CRDs live in the subchart's templates/, not in
# a crds/ directory -- which matters, because Helm never upgrades or deletes
# files in crds/, so a CRD parked there would silently never move again.
resource "helm_release" "prometheus_operator_crds" {
  name = "prometheus-operator-crds"
  # Release metadata only; the CRDs themselves are cluster-scoped.
  namespace  = "kube-system"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-operator-crds"
  # Chart 24.0.2 is appVersion v0.86.2, the version install-crds.sh pinned.
  version = "24.0.2"

  # The CRDs already exist on tiles, applied by kubectl with no Helm ownership
  # metadata, so a plain install would fail on ownership. Adopt them instead.
  # (On tiles-test they do not exist yet and are simply created.)
  take_ownership = true

  # Install only the CRDs this cluster actually consumes. The operator itself is
  # not deployed here; Alloy and the Mimir stack are the consumers of these types.
  #
  # Note on AlertmanagerConfig: this chart ships only v1alpha1, while the
  # prometheus-operator-crd-full YAML install-crds.sh used also served v1beta1,
  # so the v1beta1 version goes away. Deliberate -- nothing here reads it. Alloy's
  # mimir.alerts.kubernetes uses the v1alpha1 lister, the single
  # AlertmanagerConfig object is authored v1alpha1 in alloy-application.yaml,
  # status.storedVersions is ["v1alpha1"], and no prometheus-operator runs.
  set = [
    { name = "crds.alertmanagers.enabled", value = "false" },
    { name = "crds.prometheusagents.enabled", value = "false" },
    { name = "crds.prometheuses.enabled", value = "false" },
    { name = "crds.thanosrulers.enabled", value = "false" },
  ]

  depends_on = [module.cluster]
}

# CRDs whose consumers live in Argo CD applications other than the one that
# ships them -- OnePasswordItem shows up in argocd, cert-manager, external-dns,
# grafana, jupyterhub and static-certs; the Gateway API types are consumed by
# Cilium; Argo CD cannot bootstrap its own. The type has to exist before the
# app-of-apps sync, which is why these are installed here rather than left to
# the chart that ships them.
#
# The charts are built from upstream CRD YAML by ci-tools/crd-charts/build.py
# and pushed to GHCR by .github/workflows/publish-crd-charts.yaml. Nothing
# third-party is committed to this repo; the CRD documents land in each chart's
# templates/, not crds/, so Helm can upgrade them.
#
# Versions are duplicated between here and ci-tools/crd-charts/sources.yaml.
# Consolidating them into one Renovate-readable file is issue #720.
locals {
  crd_charts = {
    "argo-cd-crds"              = "0.1.0"
    "cert-manager-crds"         = "0.1.0"
    "external-snapshotter-crds" = "0.1.0"
    "gateway-api-crds"          = "0.1.0"
    "onepassword-crds"          = "0.1.0"
    "trust-manager-crds"        = "0.1.0"
  }
}

resource "helm_release" "crds" {
  for_each = local.crd_charts

  name = each.key
  # Release metadata only; the CRDs themselves are cluster-scoped.
  namespace  = "kube-system"
  repository = "oci://ghcr.io/symmatree/tiles/charts"
  chart      = each.key
  version    = each.value

  # These CRDs already exist on both clusters, applied by the kubectl calls this
  # replaces, with no Helm ownership metadata. Adopt rather than fail.
  take_ownership = true

  depends_on = [module.cluster]
}

# The 1Password operator's own credentials, which cannot come from 1Password the
# way every other secret in the cluster does: the operator needs these before it
# can serve any OnePasswordItem. charts/onepassword/make-secrets.sh created them
# from the bootstrap workflow's environment; Terraform reads the same two items
# directly.
#
# Typed kubernetes_* resources, not kubernetes_manifest -- the manifest resource
# "requires API access during planning time ... and thus cannot be created in the
# same apply operation" (hashicorp/kubernetes docs). Typed resources have no such
# restriction, so this plans against a cluster that does not exist yet.
provider "kubernetes" {
  host                   = "https://${module.cluster.bootstrap_ip}:6443"
  cluster_ca_certificate = base64decode(module.cluster.kubernetes_client_configuration.ca_certificate)
  client_certificate     = base64decode(module.cluster.kubernetes_client_configuration.client_certificate)
  client_key             = base64decode(module.cluster.kubernetes_client_configuration.client_key)
}

data "onepassword_item" "onepassword_operator" {
  vault = data.onepassword_vault.tf_secrets.uuid
  title = "${var.cluster_name}-onepassword-operator"
}

data "onepassword_item" "onepassword_connect_credentials" {
  vault = data.onepassword_vault.tf_secrets.uuid
  title = "${var.cluster_name}-onepassword-connect-credentials"
}

# Argo CD no longer sets CreateNamespace/managedNamespaceMetadata on the
# onepassword Application, so this is the only writer.
resource "kubernetes_namespace_v1" "onepassword" {
  metadata {
    name   = "onepassword"
    labels = { "pod-security.kubernetes.io/warn" = "baseline" }
  }

  depends_on = [module.cluster]
}

resource "kubernetes_secret_v1" "onepassword_token" {
  metadata {
    name      = "onepassword-token"
    namespace = kubernetes_namespace_v1.onepassword.metadata[0].name
  }
  data = { token = data.onepassword_item.onepassword_operator.credential }
}

resource "kubernetes_secret_v1" "op_credentials" {
  metadata {
    name      = "op-credentials"
    namespace = kubernetes_namespace_v1.onepassword.metadata[0].name
  }
  # Connect mounts this key as a file and reads it as raw JSON. Kubernetes
  # base64-encodes secret data itself, so the value here must be plain JSON --
  # an extra base64 layer produces a file Connect cannot parse.
  data = {
    "1password-credentials.json" = one([
      for f in data.onepassword_item.onepassword_connect_credentials.file :
      f.content if f.name == "1password-credentials.json"
    ])
  }
}

# Adoption of pre-existing objects is done out of band, with `terraform import`
# against the workspace that needs it -- never with an import block. An import
# block cannot satisfy a remote object that does not exist, so on a cold start,
# or after a rebuild, it fails the plan for exactly the cluster that has nothing
# to adopt. This configuration has to work on both, so it carries no import
# blocks. The onepassword namespace and secrets, and the cilium namespace, were
# adopted this way.
