# argocd-applications-installer

One chart, one resource: the `argocd-applications` Application. Terraform applies
it (`tf/nodes/k8s-argocd.tf`) as the last thing it installs, and everything else
in the cluster follows from Argo CD syncing it.

## Why it is a separate chart

The thing it renders is a `argoproj.io/v1alpha1` Application -- a custom
resource. That rules out a typed `kubernetes_*` resource, and
`kubernetes_manifest` needs API access at plan time, so it cannot be created in
the same apply as the cluster it goes into. A Helm release can.

It is not part of [`charts/argocd-applications`](../argocd-applications) because
that chart is what the Application *points at*. A chart containing an
Application that points back at the chart would be circular to read and to
render.

## The two hops

Values arrive here from Terraform and are handed down twice:

| | holds | passes to |
|---|---|---|
| `module.cluster.app_of_apps_values` | the real values | this chart, via `helm_release` |
| this chart's `valuesObject` | the same set | `charts/argocd-applications` |
| each child `application.yaml` there | the subset it needs | that component's chart |

So `values.yaml` here is the declaration of the propagated set -- the list of
values that cross from Terraform into Argo CD. Its entries are placeholders;
Terraform supplies the real ones. `scripts/helm-common.bash` reads the key names
from it so `build.sh` can render every chart offline.

Adding a propagated value means touching `module.cluster.app_of_apps_values`,
`values.yaml` here, and the `valuesObject` in `templates/application.yaml`.
Keeping those in step by hand is what issue #284 is about.

Full picture: [docs/config-propagation.md](../../docs/config-propagation.md).
