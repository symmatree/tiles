# Proxmox host monitoring (Alloy LXC)

Each **Proxmox cluster node** can run an **unprivileged LXC** with **Grafana Alloy**, bind-mounting the host root read-only at `/host` and its Alloy **config** at `/etc/alloy`. Alloy scrapes **unix/node_exporter-style** metrics (including **hwmon** via nesting + host paths), tails **host log files**, and ships everything to the **tiles** (prod) cluster over **OTLP HTTP**, with **`cluster="bond"`** and per-node **`hostname`** / **`instance`** labels.

**Config delivery (#695):** the config is uploaded as the snippet **`config.alloy`** and the snippets dir is bind-mounted over the container's **`/etc/alloy`**, so it lands at **`/etc/alloy/config.alloy`** -- exactly where the OCI image's **default entrypoint** (`/bin/alloy run /etc/alloy/config.alloy --storage.path=...`) reads it. We deliberately do **not** set `initialization.entrypoint`: the bpg provider doesn't reliably apply `initialization` settings to OCI-image containers on create ([bpg#2789](https://github.com/bpg/terraform-provider-proxmox/issues/2789)), so an overridden entrypoint is silently dropped on recreate and the CT falls back to the image's demo config -- what left the feed dark after the #692/#694 incident. Letting the default entrypoint load our config makes a recreate self-correcting.

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

Changes do not all affect a **running** CT the same way. **Config content** (`config.alloy`) updates the snippet, but a running CT keeps the old file open until restarted. **Mount and network** changes are **`ForceNew`** (recreate the CT). Practical sequence: **`terraform apply`**, then **stop/start** (or let the recreate happen). Afterward, **`/interfaces`** should list an IPv4 on **`eth0`**, and `cat /proc/1/cmdline` in the CT should show `/bin/alloy run /etc/alloy/config.alloy` loading the mounted config.

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
