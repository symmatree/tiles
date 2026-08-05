# Proxmox host monitoring (Alloy LXC)

Each **Proxmox cluster node** can run an **unprivileged LXC** with **Grafana Alloy**, bind-mounting the host root read-only at `/host` and Proxmox **snippets** at `/var/lib/vz/snippets`. Alloy scrapes **unix/node_exporter-style** metrics (including **hwmon** via nesting + host paths), tails **host log files**, and ships everything to the **tiles** (prod) cluster over **OTLP HTTP**, with **`cluster="bond"`** and per-node **`hostname`** / **`instance`** labels.

OTLP ingress and receiver behavior: [synology-monitoring.md](synology-monitoring.md).

## Source files

- [`tf/nodes/proxmox-alloy.tf`](../tf/nodes/proxmox-alloy.tf) -- OCI image, snippet upload, one LXC per node (`proxmox_root` for bind mounts)
- [`tf/nodes/templates/alloy-proxmox.alloy`](../tf/nodes/templates/alloy-proxmox.alloy) -- Alloy pipeline

## Terraform

- **Scope:** `tf/nodes`, workspace **`prod`** with **`-var-file=prod.tfvars`** for edge Alloy (cluster VMs may use test or prod workspace per environment).
- **Toggles:** **`deploy_proxmox_alloy`** and **`deploy_synology_alloy`** ([`variables.tf`](../tf/nodes/variables.tf)). Both **`true`** in **`prod.tfvars`**, **`false`** in **`test.tfvars`**.
- **CT IDs:** **`alloy_vm_base_id`** + per-node index (see tfvars; prod uses base **400**).
- **Credentials:** Proxmox **`root@pam`** for bind mounts -- [`tf/nodes/README.md`](../tf/nodes/README.md), [`docs/secrets.md`](secrets.md).
- **Provider:** **`bpg/proxmox` >= 0.104** ( **`host_managed`** on LXC NICs).
- **Networking (required):** **`network_interface.host_managed = true`** on **`eth0`** with **`ip=dhcp`**. Proxmox VE **9.1+** OCI app containers use entrypoint **`/bin/alloy`**, not **`/sbin/init`**; the guest does not run DHCP. Without **`host_managed`**, **`GET /nodes/{node}/lxc/{vmid}/interfaces`** shows **`eth0`** with no IPv4 and Alloy fails OTLP export with **`network is unreachable`** to the DHCP nameserver (site DNS is still **Raconteur** via DHCP once the CT has L3).

## Deploy / config changes

Network and entrypoint changes often do not affect a **running** CT until restart. Practical sequence: **stop** Alloy CTs, **`terraform apply`**, **start** (or apply while already stopped, then start). Afterward, **`/interfaces`** should list an IPv4 on **`eth0`**.

After removing old CTs manually, apply **`prod`** workspace with **`deploy_proxmox_alloy = true`** to recreate containers.

## Verification (Explore, tiles tenant)

**Metrics:**

```promql
rate(node_cpu_seconds_total{cluster="bond", instance=~"nuc-g.*"}[5m])
```

**Logs (when working):**

```logql
{job=~"proxmox.*"}
{host=~"nuc-g.*"}
```

**Proxmox API (eth0 has an address):** `GET /nodes/{node}/lxc/{vmid}/interfaces`

## Alloy labels and dashboards

- **Metrics job:** **`integrations/node_exporter`** (via **`prometheus.relabel "unix_node_job"`** in the Alloy template).
- **Mixin / dashboards:** filter **`cluster="bond"`** and **`instance`** = Proxmox node name (e.g. **`nuc-g2p-1`**). See **bond-mixin** and **node-exporter-mixin** in this repo.

## Related docs

- [synology-monitoring.md](synology-monitoring.md)
- [`tf/nodes/README.md`](../tf/nodes/README.md)
