# tiles
Helm, Kubernetes, Terraform kinds of things

## Network ranges

* Router claims 10.0.0.0/16.
* DHCP: 10.0.11.1 - 10.0.12.254
* 10.0.0.0/24: UniFi infrastructure
* 10.0.1.0/24: Physical Proxmox hosts + old Tales cluster nodes
  * Tales legacy: 10.0.4.0/24 (pods) - to be reclaimed
  * 10.0.8.0/24 (Tales external)
* 10.0.98.0/24: Client machines (laptops, workstations)
* 10.0.99.0/24: Servers, IoT services, cameras

### Kubernetes Clusters (Compact /22 Allocation)

* **Tiles cluster (10.0.101.0/22)**:
  * 10.0.101.0/24: VMs + VIP (VIP: 10.0.101.10)
  * 10.0.102.0/24: LoadBalancer range (Cilium L2 announcements)
  * 10.0.103.0/24: Pods (ipv4NativeRoutingCIDR)
  * 10.0.104.0/24: Services

* **Tiles-test cluster (10.0.105.0/22)**:
  * 10.0.105.0/24: VMs + VIP (VIP: 10.0.105.10)
  * 10.0.106.0/24: LoadBalancer range (Cilium L2 announcements)
  * 10.0.107.0/24: Pods (ipv4NativeRoutingCIDR)
  * 10.0.108.0/24: Services

## Recreating cluster

Edit `tiles-test.tf` and set

```
  run_bootstrap       = false
  apply_configs       = false
```

and then run

```
cd tiles/tf/nodes
terraform destroy -target \
   'module.tiles-test.module.talos-vm["tiles-test-cp"].proxmox_virtual_environment_vm.main'
terraform destroy -target \
   'module.tiles-test.module.talos-vm["tiles-test-wk"].proxmox_virtual_environment_vm.main'
```

## Talos client configuration (talosconfig)

When a cluster's VMs are started (`start_vms = true`), this repo automatically stores the Talos client configuration in 1Password as a Secure Note titled:

- `<cluster-name>-talosconfig` (e.g., `tiles-test-talosconfig`)

The talosconfig YAML is stored in the `notesPlain` field of that item.

### Retrieve talosconfig with 1Password CLI

Replace `<VAULT>` and `<CLUSTER>` below (e.g., `tiles-secrets` and `tiles-test`).

```bash
# Download talosconfig from 1Password
op read "op://<VAULT>/<CLUSTER>-talosconfig/notesPlain" > ~/.talos/<CLUSTER>.yaml

# Merge it into talosctl's config (talosctl uses ~/.talos/config)
talosctl config merge ~/.talos/<CLUSTER>.yaml

# Verify it works (use a node IP from your cluster)
talosctl -n <NODE_IP> version
```

**Important**: Use `op read` with secret reference format, not `op item get`, as the latter adds quotes around the output which breaks the YAML.

Notes:
- Production cluster uses `cluster_name = "tiles"`; test uses `"tiles-test"`.
- Items are only created when VMs are started for that cluster.
