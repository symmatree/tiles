# Argo CD. Replaces charts/argocd/bootstrap.sh (`helm template | kubectl apply`).
#
# Terraform is the only writer: the argocd Application drops automated sync in
# the same change, so Argo CD renders, diffs and reports drift on itself without
# correcting it. Self-management was the reason bootstrap.sh only had to run
# once; now the install is declared, and Argo CD's job here is visibility.
#
# The chart is the local umbrella at charts/argocd, with the same value layers
# charts/argocd/application.yaml feeds Argo CD, so the two render identical
# output -- which is what lets this adopt the live tiles install rather than
# rewrite it.
#
# Subchart tarballs (argo-cd, oauth2-proxy) are not committed; nodes-plan-apply
# runs .github/actions/helm-setup to vendor them before Terraform loads the chart.

locals {
  argocd_chart  = "${path.module}/../../charts/argocd"
  argocd_values = "${path.module}/../../charts/argocd-applications/values"
  argocd_host   = "argocd.${var.cluster_name}.symmatree.com"
}

resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
    # All three are what bootstrap.sh set and what is live on tiles. The
    # Application's managedNamespaceMetadata only ever asserted warn, so
    # enforce and trust-bundle came from the script alone.
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/warn"    = "baseline"
      "trust-bundle"                       = "enabled"
    }
  }

  depends_on = [module.cluster]
}

resource "helm_release" "argocd" {
  name      = "argocd"
  namespace = kubernetes_namespace_v1.argocd.metadata[0].name
  chart     = local.argocd_chart

  # Mirrors charts/argocd/application.yaml: the chart's own values.yaml is
  # loaded by Helm, then the shared and per-cluster overlays, then the keys Argo
  # CD templates into its valuesObject. Those templated hosts are why the
  # valuesObject exists at all -- values.yaml is not template-expanded, so the
  # domain cannot be built from cluster_name there.
  values = [
    file("${local.argocd_values}/argocd-values.yaml"),
    file("${local.argocd_values}/argocd-${var.cluster_name}-values.yaml"),
    yamlencode({
      targetRevision = module.cluster.target_revision
      cluster_name   = var.cluster_name
      vault_name     = data.onepassword_vault.tf_secrets.name
      "argo-cd" = {
        global = { domain = local.argocd_host }
        server = {
          ingressGrpc = { hostname = "grpc-argocd.${var.cluster_name}.symmatree.com" }
        }
      }
      "oauth2-proxy" = {
        ingress = {
          hosts = [local.argocd_host]
          tls = [{
            secretName = "argocd-proxy-tls"
            hosts      = [local.argocd_host]
          }]
        }
      }
    }),
  ]

  # No wait, matching the `kubectl apply` this replaces. The readiness gate
  # covers the whole release, and Argo CD's ingress cannot become ready until
  # cert-manager and external-dns exist -- which Argo CD itself deploys once the
  # app-of-apps lands. charts/argocd-applications/install-application.sh is what
  # waits for the controllers, immediately before applying the root Application.
  wait = false

  # On tiles these objects were applied by bootstrap.sh with no Helm ownership
  # metadata, so this first apply adopts them rather than failing.
  take_ownership = true

  depends_on = [module.cluster]
}
