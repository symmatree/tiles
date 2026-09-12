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

  # No wait: the readiness gate covers the whole release, and oauth2-proxy
  # cannot become ready until the 1Password operator exists -- which Argo CD
  # itself deploys once the app-of-apps tree lands. Waiting would deadlock.
  wait = false

  # On tiles these objects were applied by bootstrap.sh with no Helm ownership
  # metadata, so this first apply adopts them rather than failing.
  take_ownership = true

  depends_on = [module.cluster]
}

# The root of the app-of-apps tree.
#
# Nothing waits for argocd-redis, argocd-repo-server or
# argocd-application-controller before this is applied: the Application is a
# custom resource, so applying it before the controller runs is fine -- Argo CD
# reconciles it on startup. The ordering that matters, the AppProject existing
# first, is the graph edge below, since the AppProject ships with the Argo CD
# release.
resource "helm_release" "app_of_apps" {
  name      = "app-of-apps"
  namespace = kubernetes_namespace_v1.argocd.metadata[0].name
  chart     = "${path.module}/../../charts/app-of-apps"

  values = [yamlencode(module.cluster.app_of_apps_values)]

  # Same reason as the Argo CD release: this only applies a CR, and what it
  # triggers cannot converge until the tree it installs is running.
  wait = false

  depends_on = [helm_release.argocd]
}

# Argo CD generates an initial admin password at install and stores it in
# argocd-initial-admin-secret, which it removes once the password is changed.
# depends_on pins the read to the apply that just installed Argo CD, when the
# secret is guaranteed present.
#
# If the admin password is ever rotated, Argo CD deletes that secret and this
# data source starts failing the apply -- the shell version this replaces
# degraded to "nothing to sync" instead.
data "kubernetes_secret_v1" "argocd_initial_admin" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
  }

  depends_on = [helm_release.argocd]
}

# The full login item, not just the password: username and the primary URL are
# what let the 1Password browser extension offer this on the Argo CD login page.
resource "onepassword_item" "argocd_admin" {
  vault    = data.onepassword_vault.tf_secrets.uuid
  title    = "argocd-${var.cluster_name}-admin"
  category = "login"
  username = "admin"
  # Trailing slash is what the existing items carry; without it this shows as a
  # diff on every plan.
  url      = "https://${local.argocd_host}/"
  password = data.kubernetes_secret_v1.argocd_initial_admin.data["password"]
}
