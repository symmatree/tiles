# Cluster network

Kubernetes runs on Talos (VMs on Proxmox and bare-metal nodes where configured). This page points at the sources of truth; it does not duplicate YAML or Helm values.

## Where the numbers live

Per-cluster CIDRs, API VIP, external-IP pool, and VM IP addresses are set in Terraform workspace tfvars and wired into the Talos module from [`cluster.tf`](https://github.com/symmatree/tiles/blob/main/tf/nodes/cluster.tf): [`test.tfvars`](https://github.com/symmatree/tiles/blob/main/tf/nodes/test.tfvars) (workspace `test`, cluster `tiles-test`) and [`prod.tfvars`](https://github.com/symmatree/tiles/blob/main/tf/nodes/prod.tfvars) (workspace `prod`, cluster `tiles`). Broader site addressing (router / DHCP / which /18 is which) is summarized in [`README.md`](https://github.com/symmatree/tiles/blob/main/README.md).

## Talos

Base machine config template: [`tf/modules/talos-cluster/talos-config.yaml`](https://github.com/symmatree/tiles/blob/main/tf/modules/talos-cluster/talos-config.yaml). Cluster-specific patches (pod and service CIDRs, install image, **Layer2VIPConfig** on control plane nodes, taints, host DNS flags) are built in [`tf/modules/talos-cluster/nodes.tf`](https://github.com/symmatree/tiles/blob/main/tf/modules/talos-cluster/nodes.tf). Bootstrap and client material are in [`tf/modules/talos-cluster/main.tf`](https://github.com/symmatree/tiles/blob/main/tf/modules/talos-cluster/main.tf).

At a glance: Talos runs with CNI left to the post-bootstrap install (Cilium), kube-proxy disabled in favor of Cilium, and the Kubernetes API fronted by a layer-2 VIP. The VIP NIC link is set from [`cluster.tf`](https://github.com/symmatree/tiles/blob/main/tf/nodes/cluster.tf) to match the image schematic (`eth0` with predictable interfaces off).

## Cilium

Helm defaults and cluster overrides live in [`charts/cilium/values.yaml`](https://github.com/symmatree/tiles/blob/main/charts/cilium/values.yaml). The chart enables native routing aligned with the pod CIDR, eBPF masquerading, L2 service announcements, Gateway API and ingress controller options, and Talos-oriented agent settings. Exact toggles and interface names for L2 features belong in that file (they change with chart edits).

## DNS

- **Talos host DNS** is configured in [`tf/modules/talos-cluster/nodes.tf`](https://github.com/symmatree/tiles/blob/main/tf/modules/talos-cluster/nodes.tf). **`forwardKubeDNSToHost` must stay `false`** when using Cilium with `bpf.masquerade` enabled; turning it on has broken pod DNS in this environment (symptom: resolution failures across pods / Talos / Cilium). Upstream Talos + Cilium install docs describe the integration pattern.
- **In-cluster resolution** is the normal Kubernetes path (kubelet-provided pod `resolv.conf` to the cluster DNS Service, CoreDNS). For behavior and Corefile details, use the live `kube-system` manifests or upstream CoreDNS docs rather than copying a snapshot here.
- **Cilium** may observe or forward DNS for policy features (for example ToFQDNs); relevant Helm keys are in [`charts/cilium/values.yaml`](https://github.com/symmatree/tiles/blob/main/charts/cilium/values.yaml). Grafana mixins for CoreDNS live under the Argo-managed tanka env [`tanka/environments/coredns-mixin/main.jsonnet`](https://github.com/symmatree/tiles/blob/main/tanka/environments/coredns-mixin/main.jsonnet) (monitoring, not the CoreDNS server config).

## Proxmox VMs and the site LAN

Talos **VM** nodes are created by [`tf/modules/talos-vm/main.tf`](https://github.com/symmatree/tiles/blob/main/tf/modules/talos-vm/main.tf): each VM has a single virtio NIC on Proxmox **`vmbr0`**, and Terraform creates a matching **UniFi fixed client** (`unifi_user`) with the same MAC, IP, and network membership. The UniFi network is selected by name in [`tf/nodes/cluster.tf`](https://github.com/symmatree/tiles/blob/main/tf/nodes/cluster.tf) via `data "unifi_network"` and `var.unifi_network_name` from tfvars.

So these nodes are ordinary routed hosts on the UniFi-managed LAN; Proxmox only provides the hypervisor, bridge attachment, and static MAC. Pod and service CIDRs are additionally advertised or routed per Cilium as in [`charts/cilium/values.yaml`](https://github.com/symmatree/tiles/blob/main/charts/cilium/values.yaml). There is no separate "mystery layer" between the VM NIC and site routing beyond that bridge and your existing UniFi IP plan.

Bare-metal Talos nodes (if present for a workspace) follow [`tf/modules/talos-cluster/nodes.tf`](https://github.com/symmatree/tiles/blob/main/tf/modules/talos-cluster/nodes.tf) / [`variables.tf`](https://github.com/symmatree/tiles/blob/main/tf/modules/talos-cluster/variables.tf) for UniFi registration and machine config; see also [`docs/bare-metal-nodes.md`](bare-metal-nodes.md).

## External references

- Talos [Layer2VIPConfig](https://docs.siderolabs.com/talos/v1.13/reference/configuration/network/layer2vipconfig)
- Cilium [Kubernetes installation (Helm)](https://docs.cilium.io/en/stable/installation/k8s-install-helm/) (Talos-oriented notes there)
