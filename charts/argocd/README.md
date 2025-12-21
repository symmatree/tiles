# argocd

## Interesting Notes

### Cluster Bootstrap

At cluster setup, ArgoCD is bootstrapped with a `helm template` piped to `kubectl apply` in
`charts/bootstrap.sh`. This is sufficient to run headless; the Ingress won't work
properly until `external-dns` and `cert-manager` are up. We then install the `argocd-applications`
chart which includes `charts/argocd/application.yaml`, which has autosync turned on. ArgoCD
then syncs over itself (mostly to add a tracking annotation) and from then on is self-managed.

### Tanka (jsonnet) plugin

I'm using Tanka to define a directory structure and combine jsonnet-bundler and compiler
invocations. To be honest this is probably a small increment over just using them directly,
given that I don't use the Tanka `tk` binary to diff or apply or anything (ArgoCD
just uses it to template like it does Helm charts). But I'm not used to using them directly
thanks to bazel at work, so this is simple.

The actual plugin is stolen and then adapted to the current Argo plugin system. It's implemented
in

* `charts/argocd/templates/tanka.yaml` which defines a ConfigMap with the commands to discover, initialize
  and install applications
* `charts/argocd/values.yaml`, under `argo-cd.repoServer.extraContainers` which defines a container that
  installs `jb` and `tk`, mounts various resources including the ConfigMap as `plugin.yaml`, and runs the
  `argocd-cmp-server` standard binary. Note that this config would be smaller with an image with the
  tools preinstalled, rather than fetching them on startup, but then we'd have a whole image to build and
  maintain.
