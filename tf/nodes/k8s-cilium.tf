# Cilium, the CNI. Replaces charts/cilium/bootstrap.sh (`helm template |
# kubectl apply`).
#
# Terraform is the only writer: the cilium Application drops automated sync in
# the same change, so Argo CD reports drift on this chart without correcting it.
#
# The chart is the local umbrella at charts/cilium, not the upstream chart
# directly, so Terraform and Argo CD render byte-identical output from the same
# values -- which is what lets this first apply adopt the live tiles install
# without rewriting it. The
# umbrella carries no templates of its own; it exists to pin the version and
# nest values under the `cilium` subchart key.
#
# The subchart tarball must be vendored before Terraform runs: nodes-plan-apply
# calls .github/actions/helm-setup, which runs ci-tools/helm-update-all.sh.

locals {
  cilium_chart  = "${path.module}/../../charts/cilium"
  cilium_values = "${path.module}/../../charts/argocd-applications/values"
}

resource "kubernetes_namespace_v1" "cilium" {
  metadata {
    name = "cilium"
    # Matches the cilium Application's managedNamespaceMetadata, which is what
    # is actually live on tiles. (bootstrap.sh set warn=baseline; Argo won.)
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }

  depends_on = [module.cluster]
}

resource "helm_release" "cilium" {
  name      = "cilium"
  namespace = kubernetes_namespace_v1.cilium.metadata[0].name
  chart     = local.cilium_chart

  # Mirrors charts/cilium/application.yaml: the chart's own values.yaml is
  # loaded by Helm, then the shared and per-cluster overlays, then the keys
  # Argo CD templates into its valuesObject.
  values = [
    file("${local.cilium_values}/cilium-values.yaml"),
    file("${local.cilium_values}/cilium-${var.cluster_name}-values.yaml"),
    yamlencode({
      cilium = {
        ipv4NativeRoutingCIDR = var.pod_cidr
        cluster               = { name = var.cluster_name }
      }
    }),
  ]

  # Wait, so everything after this starts against a cluster that can actually
  # schedule. This is only satisfiable because Hubble is off in
  # charts/cilium/values.yaml -- with it on, the release gates on certs
  # cert-manager has not been installed to issue yet. It also requires every
  # registered Node to be real: a stale Node object (#641) holds a Pending
  # DaemonSet pod and will hang this for the full timeout.
  wait    = true
  timeout = 900

  # On tiles the objects were applied by bootstrap.sh with no Helm ownership
  # metadata, so this first apply adopts them rather than failing.
  take_ownership = true

  depends_on = [module.cluster]
}
