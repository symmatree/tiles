# Cilium, the CNI. Replaces charts/cilium/bootstrap.sh (`helm template |
# kubectl apply`) for clusters where var.deploy_cilium is set.
#
# Rolled out per-cluster on purpose. tiles-test has no Argo CD at all, so
# Terraform installing Cilium there creates no second writer. tiles is still
# synced by the cilium Application, and moving it means dropping that
# Application's automated sync in the same change so ownership never overlaps.
#
# The chart is the local umbrella at charts/cilium, not the upstream chart
# directly, so Terraform and Argo CD render byte-identical output from the same
# values -- which is what makes adopting the prod install safe later. The
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
  count = var.deploy_cilium ? 1 : 0

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
  count = var.deploy_cilium ? 1 : 0

  name      = "cilium"
  namespace = kubernetes_namespace_v1.cilium[0].metadata[0].name
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
        hubble = {
          tls = {
            auto = {
              certManagerIssuerRef = { name = "${var.cluster_name}-ca-issuer" }
            }
          }
          ui = {
            ingress = {
              hosts = ["hubble.${var.cluster_name}.symmatree.com"]
              tls = [{
                secretName = "hubble-ui-tls"
                hosts      = ["hubble.${var.cluster_name}.symmatree.com"]
              }]
            }
          }
        }
      }
    }),
  ]

  # Cilium is the CNI, so on a cold cluster nothing can schedule until it is up;
  # waiting here is what makes later releases meaningful rather than racing it.
  wait    = true
  timeout = 900

  # On tiles the objects were applied by bootstrap.sh with no Helm ownership
  # metadata. Set now so enabling prod later is a values change, not a
  # behavioural one.
  take_ownership = true

  depends_on = [module.cluster]
}
