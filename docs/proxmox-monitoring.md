# Proxmox host monitoring (Alloy LXC)

Each **Proxmox cluster node** can run a **privileged LXC** with **Grafana Alloy**, bind-mounting the host root read-only at `/host` and Proxmox **snippets** at `/var/lib/vz/snippets`. Alloy scrapes **unix/node_exporter-style** metrics (including **hwmon** via nesting + host paths), reads the **host systemd journal**, and ships everything to the **tiles** (prod) cluster over **OTLP HTTP**, with **`cluster="bond"`** and per-node **`hostname`** / **`instance`** labels.

> **Why privileged?** The CT must be **privileged** to read the host journal (#686). Host journal files are `0640 root:systemd-journal`; in an *unprivileged* CT the container's root maps to host uid 100000, so through the read-only `/host` bind mount those files appear owned by `nobody:nogroup` and are unreadable -- `loki.source.journal` silently reads nothing (it opens the world-readable directory but cannot read the files, so there is no loud error -- which is why the gap went unnoticed for 90d). A privileged CT's root **is** host root, so it can read them. Metrics/hwmon never needed this (they read world-readable `/proc` and `/sys` via nesting). Trade-off: the CT can now read every root-owned file under the read-only `/host` mount.

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

The **`unprivileged` -> privileged** flip (#686) cannot be toggled on a live CT: `terraform apply` **destroys and recreates** each Alloy CT. Verify afterward that host journal logs arrive with `{job="proxmox-journal"}` in Loki -- because an unreadable journal fails **silently** (no unhealthy component), the Loki query is the check, not component health.

After removing old CTs manually, apply **`prod`** workspace with **`deploy_proxmox_alloy = true`** to recreate containers.

## Verification (Explore, tiles tenant)

**Metrics:**

```promql
rate(node_cpu_seconds_total{cluster="bond", instance=~"nuc-g.*"}[5m])
# host RAM -- should read ~15.4 GB, not 0.5 GB (#544)
node_memory_MemTotal_bytes{cluster="bond", instance=~"nuc-g.*"}
```

`node_exporter` reads the host's procfs, sysfs, and rootfs, all bind-mounted under `/host` (`procfs_path = /host/proc`, `sysfs_path = /host/sys`, `rootfs_path = /host`; see [`proxmox-alloy.tf`](../tf/nodes/proxmox-alloy.tf)), so `node_memory_*` reports **host** RAM/swap. Reading the container's own `/proc/meminfo` instead reports the ~512 MB **LXC cgroup** limit (lxcfs-virtualized), which is the #544 blindspot. The `/`->`/host` bind is non-recursive, so `/proc` and `/sys` are bound explicitly.

**Logs (host systemd journal):**

```logql
{job="proxmox-journal"}
{host=~"nuc-g.*"}
{job="proxmox-journal", unit="pveproxy.service"}
```

The journal reader stamps `job="proxmox-journal"`, `host="<node>"`, and promotes the systemd unit to a `unit` label (see `loki.relabel "journal"` in the template). Before #686 the template tailed `/var/log/{syslog,messages,auth.log,daemon.log}`, which never exist on journald-only PVE 9 hosts, so `{job=~"proxmox.*"}` was empty for 90d.

**Proxmox API (eth0 has an address):** `GET /nodes/{node}/lxc/{vmid}/interfaces`

## Alloy labels and dashboards

- **Metrics job:** **`integrations/node_exporter`** (via **`prometheus.relabel "unix_node_job"`** in the Alloy template).
- **Mixin / dashboards:** filter **`cluster="bond"`** and **`instance`** = Proxmox node name (e.g. **`nuc-g2p-1`**). See **bond-mixin** and **node-exporter-mixin** in this repo.

## Related docs

- [synology-monitoring.md](synology-monitoring.md)
- [`tf/nodes/README.md`](../tf/nodes/README.md)
