# tiles
Helm, Kubernetes, Terraform kinds of things

## Documentation submodule (`fables/`)

This repo includes a `fables/` git submodule which contains the published documentation/knowledge base pages (including cluster and node docs, software notes, etc.).
If the documentation changes upstream, you may need to update the `fables/` submodule pointer occasionally to stay aligned with the repo state.

## Network ranges

* Router claims 10.0.0.0/16.
* DHCP: 10.0.11.1 - 10.0.12.254
* 10.0.0.0/24: UniFi infrastructure
* 10.0.1.0/24: Physical Proxmox hosts + old Tales cluster nodes
  * Tales legacy: 10.0.4.0/23 (pods), 10.0.6.0/23 (services) - to be reclaimed
  * 10.0.8.0/24 (Tales external)
* 10.0.98.0/24: Client machines (laptops, workstations)
* 10.0.99.0/24: Servers, IoT services, cameras

### Kubernetes Clusters

Each cluster uses `/18` allocation (64 /24s). Pods use `/20` with `node-cidr-mask-size: 24`, providing 256 hosts per node and supporting up to 16 nodes maximum.

* **Tiles cluster (10.0.128.0/18)**:
  * 10.0.128.0/24: VMs + VIP (VIP: 10.0.128.10)
  * 10.0.129.0/24: External IPs (Cilium IPAM handles IPAM for LoadBalancers, which are also advertised via L2 announcements)
  * 10.0.136.0/21: Services (10.0.136.0 - 10.0.143.255)
  * 10.0.144.0/20: Pods (10.0.144.0 - 10.0.159.255, ipv4NativeRoutingCIDR) with `node-cidr-mask-size: 24`
  * 10.0.160.0/24 - 10.0.191.255: Reserved for future use

* **Tiles-test cluster (10.0.192.0/18)**:
  * 10.0.192.0/24: VMs + VIP (VIP: 10.0.192.10)
  * 10.0.193.0/24: External IPs (Cilium IPAM handles IPAM for LoadBalancers, which are also advertised via L2 announcements)
  * 10.0.200.0/21: Services (10.0.200.0 - 10.0.207.255)
  * 10.0.208.0/20: Pods (10.0.208.0 - 10.0.223.255, ipv4NativeRoutingCIDR) with `node-cidr-mask-size: 24`
  * 10.0.224.0/24 - 10.0.255.255: Reserved for future use

**Note**: External IPs are IPs allocated outside the cluster's pod/service spaces that are accessible to the rest of the network. Cilium IPAM handles IPAM for LoadBalancers, which are also advertised via L2 announcements.

## Recreating cluster

Use this when you want **new Proxmox VMs** (fresh disks / reinstall Talos), for example after a major Talos pin change. Workspaces are **`test`** and **`prod`**; pick one and stay consistent through the apply. This flow uses GitHub Actions (service account, VPN, secrets) end to end.

1. Run **[`taint-vms`](.github/workflows/taint-vms.yaml)** in Actions. Enable **taint test** and/or **taint prod** (each taints the Talos VM resources for that workspace and **`talos_machine_bootstrap`** so bootstrap runs again after disks are new).
2. Run **`nodes-plan-apply`** with **apply** for the workspace you tainted: a push to **`main`** applies **test** by default; use **`workflow_dispatch`** with apply and **prod** for production.

After apply, Terraform recreates the VMs, applies machine config, and bootstraps the cluster.

See `docs/environment-strategy.md` for workspace behavior.

## Talos client configuration (talosconfig)

Download talosconfigs for both clusters as described in [secrets.md](docs/secrets.md#talos-client-configuration-talosconfig). Use `talosctl` with the `--talosconfig` flag to specify which cluster to connect to:

```bash
# Verify connection to tiles (production) cluster
talosctl --talosconfig ~/.talos/tiles.yaml -n <NODE_IP> version

# Verify connection to tiles-test cluster
talosctl --talosconfig ~/.talos/tiles-test.yaml -n <NODE_IP> version
```

**Note**: The `talosctl config merge` command has certificate validation issues. Always use `--talosconfig` explicitly instead of merging configs.
