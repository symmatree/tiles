# Monitoring Mixins

<https://monitoring.mixins.dev/> has reasonable backstory, but there's a frustrating
gap all around: there's no completely obvious way to collect, customize and install
them.

## Kubernetes for everything

My current approach is to use my Tanka plugin in ArgoCD to generate k8s resources
(both Prometheus Operator objects and ConfigMaps in the format Grafana likes), and
have it manage them. Then Alloy reads the operator objects and pushes them to Mimir's
Ruler, and Grafana's sidecar reads the ConfigMaps, writes them to a locally-shared
disk, and tells Grafana to load them.

This actually works well enough. The downsides are

* These are massive chunks of config with no real kubernetes structure, so it's kind
  of wasteful to use ArgoCD. It almost certainly increases the memory of the repo-server,
  doesn't play well in the UI if you do click into it, and so forth.
* There doesn't seem to be a canonical library to actually do this; I have written my own
  jsonnet stubs to wrap the mixin output in appropriate structure which works but feels fragile.
* Debugging is a little roundabout; you declare config then go read the logs of the
  respective tool to see if it got it and loaded it right.

## Customizing

Gitlab has a pretty good [utility library](https://gitlab.com/gitlab-com/gl-infra/monitoring-mixins/-/blob/main/jsonnet-libs/mixin-utils/utils.libsonnet) for removing alerts, which is key for mixins that
have inappropriate assumptions for your system (and don't offer a config mechanism that would
address it).

## Rejected options

### mimirtool and grafana api

An option is to push the alert and dashboad configs using the respective CLI tools or
APIs. This is direct, avoids the overhead of going through Kubernetes, and even has a
chance of better error messages. I would worry about diffing and pruning if this was
run steadily; if not there's a risk of drift in the live config, rot in the git repo,
and generally the risk of the inability to run it later when you need it.

### Filesystem provisioning

We could push the dashboards and rules through files referenced in config files, the
way you would in a local install. Of course it would be foolish to do that by
assembling ConfigMaps into a filesystem, because that's what the sidecar and ruler
would do with a lot less effort. So this would be something like baking the configs
into an image.

Given how much wiring the Mimir and Grafana helm charts do, I'd be worried that any
extensive customization at the file system level would collide with their present
or future config-assembly and integrations; overall I think this might be the way
to do it if I was doing a hand-managed minimal deployment, like a single-binary-mode
Mimir with a config that enables only what we need.
