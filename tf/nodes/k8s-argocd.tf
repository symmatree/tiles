# Argo CD, and the Application that hands the rest of the cluster over to it.
# Why Terraform installs this at all, and why Argo CD does not sync itself:
# tf/nodes/README.md and docs/config-propagation.md.

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

  # The same layers charts/argocd/application.yaml gives Argo CD, so both render
  # identical output. values.yaml is not template-expanded, which is why the
  # hosts are built here rather than there.
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

  # oauth2-proxy cannot become ready until the 1Password operator exists, and
  # Argo CD is what deploys it, so a readiness gate here deadlocks.
  wait = false

  # The live objects predate this release and carry no Helm ownership metadata.
  take_ownership = true

  depends_on = [module.cluster]
}

# Applies the argocd-applications Application, after which Argo CD owns the
# rest of the cluster. See charts/argocd-applications-installer/README.md and
# docs/config-propagation.md.
resource "helm_release" "argocd_applications_installer" {
  name      = "argocd-applications-installer"
  namespace = kubernetes_namespace_v1.argocd.metadata[0].name
  chart     = "${path.module}/../../charts/argocd-applications-installer"

  values = [yamlencode(module.cluster.app_of_apps_values)]

  # Applying a custom resource; Argo CD reconciles it when its controller is
  # ready, which may be after this returns.
  wait = false

  # The argocd-applications Application already exists on both clusters, applied
  # by kubectl and since owned by Argo CD, with no Helm ownership metadata.
  take_ownership = true

  depends_on = [helm_release.argocd]
}

# The local admin login, which is how you reach Argo CD before SSO works --
# Google login needs external-dns and cert-manager, which Argo CD deploys
# itself. depends_on pins the read to the apply that installs Argo CD, since
# that is what generates the secret.
# charts/argocd/README.md#access--endpoints
data "kubernetes_secret_v1" "argocd_initial_admin" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
  }

  depends_on = [helm_release.argocd]
}

# A full login, not a bare password: the extension needs username and URL to
# offer it on the login page.
resource "onepassword_item" "argocd_admin" {
  vault    = data.onepassword_vault.tf_secrets.uuid
  title    = "argocd-${var.cluster_name}-admin"
  category = "login"
  username = "admin"
  # Trailing slash matches the existing items; without it, a diff every plan.
  url      = "https://${local.argocd_host}/"
  password = data.kubernetes_secret_v1.argocd_initial_admin.data["password"]
}
