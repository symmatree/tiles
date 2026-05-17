# Proxmox host monitoring (Alloy LXC)

Each **Proxmox cluster node** can run an **unprivileged LXC** with **Grafana Alloy**, bind-mounting the host root read-only at `/host` and Proxmox **snippets** at `/var/lib/vz/snippets`. Alloy scrapes **unix/node_exporter-style** metrics (including **hwmon** via nesting + host paths), tails **host log files**, and ships everything to **both** Kubernetes clusters over **OTLP HTTP**, with **`cluster="bond"`** and per-node **`hostname`** / **`instance`** labels.

Implementation is intended to mirror the Synology pattern; OTLP ingress and receiver behavior are described in [synology-monitoring.md](synology-monitoring.md).

## Source files

- **[`tf/nodes/proxmox-alloy.tf`](../tf/nodes/proxmox-alloy.tf)** -- OCI image pull, snippet upload, one LXC per Proxmox node (`proxmox_root` provider for bind mounts)
- **[`tf/nodes/templates/alloy-proxmox.alloy`](../tf/nodes/templates/alloy-proxmox.alloy)** -- Alloy pipeline (unix exporter, scrape, OTLP, log tailers, attribute processor)

## Terraform behavior

- **Scope:** `tf/nodes` with workspace **`test`** or **`prod`** and the matching **`-var-file`** (`test.tfvars` / `prod.tfvars`).
- **Toggle:** **`deploy_proxmox_alloy`** (see [`variables.tf`](../tf/nodes/variables.tf)). When **`false`**, no OCI image, snippet, or LXC resources are created.
  - As of the values checked in-repo: **`test.tfvars`** sets **`deploy_proxmox_alloy = true`**; **`prod.tfvars`** sets **`deploy_proxmox_alloy = false`** (duplicate reporting / rollout control until you flip it).
- **CT IDs:** **`alloy_vm_base_id`** plus per-node index (cluster-wide unique VMID); **`test.tfvars`** and **`prod.tfvars`** use different bases (see tfvars).
- **Credentials:** Proxmox **`root@pam`** for the provider that performs bind mounts; see [`tf/nodes/README.md`](../tf/nodes/README.md) and [`docs/secrets.md`](secrets.md).
- **Networking:** Alloy CTs use **`ip=dhcp`** with **`host_managed = true`** on **`eth0`** (Proxmox VE **9.1+**, **`bpg/proxmox` >= 0.104**). OCI application containers run **`/bin/alloy`** as entrypoint, not **`/sbin/init`**, so the guest does not configure DHCP itself; the host must. Without **`host_managed`**, **`/nodes/{node}/lxc/{vmid}/interfaces`** can show **`eth0`** with no IPv4 and Alloy logs **`network is unreachable`** when exporting to OTLP (DNS never leaves the CT). Site DNS remains **Raconteur (`10.0.99.1`)** via DHCP; do not override nameserver in Terraform unless you intend to bypass that design.

## Alloy configuration (repo truth)

- **Metrics:** `prometheus.exporter.unix` uses **`/proc`**, **`/sys`**, **`/host`** (nesting exposes host proc/sys to the guest per Proxmox docs). **`prometheus.scrape "node"`** sets **`job_name = "integrations/node_exporter"`** so generated dashboards (for example **node-exporter-mixin**) can target the same job name as in-cluster node_exporter scrapes.
- **OTLP:** Duplicate exporters to **`https://otlp.tiles-test.symmatree.com`** and **`https://otlp.tiles.symmatree.com`** with **`X-Scope-OrgID`** **`tiles-test`** / **`tiles`** respectively.
- **Labels (attributes processor):** **`cluster="bond"`**, **`hostname="<proxmox node name>"`**, **`instance="<proxmox node name>"`** ( **`instance`** is set so mixin queries that filter on **`instance`** resolve; **`hostname`** is the Terraform `each.value` node name, e.g. **`nuc-g2p-1`**).
- **Logs:** `loki.source.file` on **`/host/var/log/syslog`**, **`messages`**, **`auth.log`**, **`daemon.log`** with jobs **`proxmox-syslog`**, **`proxmox-messages`**, **`proxmox-auth`**, **`proxmox-daemon`** and **`host`** set to the node name.

## Operational notes

- **Snippet path:** Config is uploaded as a Proxmox **snippet** and mounted in the CT at **`/var/lib/vz/snippets/alloy-proxmox.alloy`** (same path on host and guest).
- **Alloy UI:** Entrypoint sets **`--server.http.listen-addr=0.0.0.0:12345`** (see `proxmox-alloy.tf`). Reachability depends on your LAN/firewall; it is not the same as the Synology DSM port.
- **Entrypoint / network / config updates:** Comment in **`proxmox-alloy.tf`**: after changing entrypoint, **`host_managed`**, or config, the first apply may not refresh a running CT; **stop** the CTs in the Proxmox UI, then **apply** or **start** so they pick up the new settings. After **`host_managed`** is applied, confirm **`GET .../lxc/{vmid}/interfaces`** shows an IPv4 on **`eth0`** and Alloy export errors stop.

## Findings from Mimir / Loki checks (point-in-time)

These observations were from **Grafana MCP** queries against **tiles-test** (and sometimes **tiles**) Mimir/Loki while debugging; they are **not** a guarantee of current production state. Re-run Explore if you need today’s picture.

- **`cluster="bond"` and Synology:** Older debugging saw unix host metrics as **`job="integrations/unix"`** because **`prometheus.exporter.unix`** stamps that label and **`otelcol.receiver.prometheus`** prefers it over **`prometheus.scrape` `job_name`**. **Synology and Proxmox** Alloy configs now include **`prometheus.relabel "unix_node_job"`** so unix metrics should match **`job="integrations/node_exporter"`** after redeploy; SNMP jobs are unchanged (**`integrations/snmp/...`**).
- **Proxmox in Mimir:** Expect **`job="integrations/node_exporter"`** for unix scrapes after the relabel above. When Proxmox LXCs are not running, **`deploy_proxmox_alloy`** is **false**, or OTLP path is broken, you will **not** see per-node **`nuc-*`** series under **`cluster="bond"`** even though the Terraform template sets **`hostname`** / **`instance`** to those names.
- **Cardinality APIs vs instant queries:** **`list_prometheus_label_values`** sometimes listed **`nuc-*`** **`hostname`** values while **instant** selectors on **`hostname`** returned **no** series. Treat **instant/range** queries in Explore as ground truth for “is this shipping **now**?”.

## Loki (logs)

- **Intended** streams include **`job`** values **`proxmox-*`** and **`host`** equal to the Proxmox node name (see Alloy template).
- **Observed in one debugging pass:** Loki **`job`** catalogs in the **tiles-test** tenant showed **`synology-*`** jobs with traffic; **`proxmox-*`** did not show up in the same way. **Hypothesis (not verified here):** logs may not have been ingested for Proxmox at that time (LXCs off, paths empty, or OTLP logs path differs from metrics). Confirm with **`{host=~"nuc.*"}`** or **`{job=~"proxmox.*"}`** in Explore after you believe the LXCs are up.

## Dashboards

- **node-exporter-mixin** in this repo uses **`job="integrations/node_exporter"`** and a visible **Cluster** variable when **`showMultiCluster`** is enabled. For Proxmox hosts you want **`cluster="bond"`** and an **`instance`** matching the Proxmox node name, assuming those series exist in Mimir.

## Related docs

- [synology-monitoring.md](synology-monitoring.md) -- Raconteur Alloy, OTLP, verification queries, **`cluster="bond"`** vs Loki tenant **`cluster`**.
- [`tf/nodes/README.md`](../tf/nodes/README.md) -- Proxmox root env var for Terraform.
