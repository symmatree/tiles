# Synology (Raconteur) monitoring

`raconteur.ad.local.symmatree.com` (Synology NAS) is monitored by a single **Grafana Alloy** container that ships metrics and logs to the **tiles** (prod) cluster over OTLP.

## Architecture

The Alloy container on the NAS collects:

1. **Host metrics** via `prometheus.exporter.unix` (node_exporter-style), scraping paths under `/host/proc`, `/host/sys`, `/host`
2. **Hardware metrics** via `prometheus.exporter.snmp` (Synology OIDs, SNMP v3)
3. **Log files** via `loki.source.file` under `/host/var/log` (messages, synolog, auth, daemon)

Metrics pass through `otelcol.receiver.prometheus` and logs through `otelcol.receiver.loki`; both are labeled with **`cluster="bond"`** in the OTLP payload (attributes) and forwarded to prod:

- `https://otlp.tiles.symmatree.com`

Headers set **`X-Scope-OrgID`** to **`tiles`**. Ingress terminates TLS and forwards to **`alloy-alloy-receiver`** (HTTP OTLP, port **4318**) in namespace **`alloy`**. See [`charts/argocd-applications/templates/alloy-application.yaml`](../charts/argocd-applications/templates/alloy-application.yaml).

### Terraform deploy flag

In [`tf/nodes/synology-alloy.tf`](../tf/nodes/synology-alloy.tf), `synology_container_project.alloy` is created when **`deploy_synology_alloy = true`** in the active **`-var-file`**. Edge Alloy is enabled in **`prod.tfvars`** only; apply from **`tf/nodes`** with **`terraform workspace select prod`** and **`-var-file=prod.tfvars`**.

## Raconteur setup

SNMP v3 is enabled on the Synology. Credentials live in 1Password at `op://tiles-secrets/raconteur-snmp`:

- `username`: SNMP v3 username
- `password`: Auth password (SHA)
- Privacy password: item field **`PRIVACY_PASSWORD`** (section `privacy`, AES) -- wired in Terraform via [`../modules/onepassword_field`](../modules/onepassword_field) as in `synology-alloy.tf`

Synology Control Panel settings (reference):

- SNMP v3 only
- Auth: SHA, Privacy: AES
- Device name: `raconteur.ad.local.symmatree.com`
- Device location: `bond-basement`
- Contact: symmetry@pobox.com

MIB pack: <https://global.download.synology.com/download/Document/Software/DeveloperGuide/Firmware/DSM/All/enu/Synology_MIB_File.zip>

## MIB generation

The SNMP exporter generator needs Synology MIBs plus standard IETF MIBs. Repo helper: [`tf/nodes/templates/copy-snmp-mibs.sh`](../tf/nodes/templates/copy-snmp-mibs.sh) (run from a checkout of `net-snmp` **`mibs`** directory, with `SNMP_EXPORTER_MIBS_DIR` set). `bash -n` on that script succeeds in CI-style checks.

### Generate `snmp.yml`

Install net-snmp dev headers, then inject secrets and run the generator (paths are examples):

```bash
sudo apt-get install -y libsnmp-dev

TILES_DIR="/path/to/tiles"
SNMP_EXPORTER_DIR="/path/to/snmp_exporter"

cd "$SNMP_EXPORTER_DIR/generator"

op inject -i "$TILES_DIR/tf/nodes/templates/generator.yml" -o ./generator.yml
go run . generate -m ./mibs
rm ./generator.yml

mv snmp.yml "$TILES_DIR/tf/nodes/templates/snmp-synology-raw.yml"
```

Edit the result into the tracked template [`tf/nodes/templates/snmp-synology.yml`](../tf/nodes/templates/snmp-synology.yml) (replace embedded auth with Terraform template variables) before committing. The generator embeds auth in `snmp.yml`; do not commit raw generated secrets.

The template input for `op inject` is **`generator.yml`** (not `generator.yml.tpl`).

## Implementation details

### Files

- **[`tf/nodes/synology-alloy.tf`](../tf/nodes/synology-alloy.tf)**: Synology Container Project, bind-mount `/` to `/host`, configs for Alloy + SNMP, host network + host PID, Alloy listens on **`0.0.0.0:12345`**
- **[`tf/nodes/templates/alloy-synology.alloy`](../tf/nodes/templates/alloy-synology.alloy)**: Unix exporter, SNMP exporter (target `raconteur.ad.local.symmatree.com:161`), scrapes, OTLP exporters, log tailers
- **[`tf/nodes/templates/snmp-synology.yml`](../tf/nodes/templates/snmp-synology.yml)**: SNMP module `synology`, auth `synology_v3`

### Metrics (Mimir)

Alloy sets **`job_name = "integrations/node_exporter"`** on the **`prometheus.scrape "node"`** block. **`prometheus.exporter.unix`** also sets **`job="integrations/unix"`** on metric labels; **`otelcol.receiver.prometheus`** uses that label for OTLP **`service.name`** (and thus Mimir **`job`**) instead of the scrape **`job_name`**. The Synology Alloy config adds **`prometheus.relabel "unix_node_job"`** so unix host metrics arrive as **`job="integrations/node_exporter"`**; SNMP scrapes are unchanged. After deploy, verify in Mimir:

- **`cluster="bond"`**
- **`instance="raconteur"`**
- **`job="integrations/node_exporter"`** (unix host metrics)

SNMP metrics have been observed with:

- **`cluster="bond"`**
- **`job="integrations/snmp/raconteur"`**
- **`instance="prometheus.exporter.snmp.synology"`**

Use these labels in **Grafana Explore** (Mimir / Prometheus datasource) when debugging.

### Logs (Loki)

Log streams use **`host="raconteur"`** and **`job`** per tailer, for example:

- `synology-syslog` -- `/host/var/log/messages`
- `synology-synolog` -- `/host/var/log/synolog/*.log`
- `synology-auth` -- `/host/var/log/auth.log`
- `synology-daemon` -- `/host/var/log/daemon.log`

Loki also carries the **Kubernetes tenant** label **`cluster="tiles"`**, matching the org that received OTLP. The **bond** grouping appears inside the JSON log line under **`attributes.cluster`** (and similar) after OTLP decoding.

## Verifying metrics and logs

Use **Grafana Explore** on the Mimir and Loki datasources for the **tiles** cluster (`borgmon.tiles.symmatree.com`).

### Mimir (PromQL)

Examples (instant or range):

```promql
count by (job, instance) (node_cpu_seconds_total{cluster="bond"})
```

```promql
topk(5, count by (__name__) ({cluster="bond", job="integrations/snmp/raconteur"}))
```

```promql
group by (job, instance) (up{cluster="bond"})
```

Expect unix + SNMP jobs as in **Metrics (Mimir)** above.

### Loki (LogQL)

Examples:

```logql
{host="raconteur"}
```

```logql
{job=~"synology.*"}
```

```logql
sum by (job) (count_over_time({host="raconteur"}[24h]))
```

### Optional: CLI against Loki / Mimir

If you install **logcli** or **mimirtool** and have tenant auth, you can run equivalent queries from the shell. This repo does not pin those tools; Grafana Explore is the supported path for ad hoc checks.

From a network that can reach the cluster, you can also **port-forward** the Loki gateway or Mimir query frontend and run `logcli query` / PromQL HTTP APIs yourself (see cluster runbooks for service names).

## Troubleshooting

### Alloy UI vs DSM

- **DSM (web admin):** `https://raconteur.ad.local.symmatree.com:5001/` (or the NAS IP)
- **Alloy HTTP UI:** `http://raconteur.ad.local.symmatree.com:12345/` (host networking; plain HTTP on port **12345**, not 5001)

Component URLs (examples):

- OTLP HTTP exporter: `http://raconteur.ad.local.symmatree.com:12345/component/otelcol.exporter.otlphttp.tiles`
- SNMP exporter: `http://raconteur.ad.local.symmatree.com:12345/component/prometheus.exporter.snmp.synology`

### SNMP scrape failures

1. **Alloy UI:** Check `prometheus.exporter.snmp.synology` and downstream `prometheus.scrape "snmp"` for errors.
2. **Synology:** Control Panel > **Terminal & SNMP** > SNMP (service enabled, v3 user matches 1Password).
3. **From your workstation** (after `op signin`), test SNMP to the same target Alloy uses (`raconteur.ad.local.symmatree.com:161`):

   ```bash
   eval "$(op signin)"
   snmpwalk -v3 -l authPriv \
     -u "$(op read op://tiles-secrets/raconteur-snmp/username)" \
     -a SHA -A "$(op read op://tiles-secrets/raconteur-snmp/password)" \
     -x AES -X "$(op read op://tiles-secrets/raconteur-snmp/PRIVACY_PASSWORD)" \
     raconteur.ad.local.symmatree.com:161 \
     1.3.6.1.4.1.6574.1
   ```

   The privacy secret URI matches [`tf/nodes/templates/generator.yml`](../tf/nodes/templates/generator.yml). If `op read` fails, run `op item get raconteur-snmp` and use the field reference shown for **PRIVACY_PASSWORD**.

4. **Mounted SNMP config:** In the container, path is **`/etc/snmp_exporter/snmp.yml`** (see `synology-alloy.tf` configs). Confirm Terraform rendered the template (no stray `${...}` placeholders).

5. **Debug logs:** In `synology-alloy.tf`, add to `environment` (check current Alloy docs for the exact variable; common pattern):

   ```hcl
   ALLOY_LOG_LEVEL = "debug"
   ```

   Redeploy the container project.

### No metrics in Mimir

1. Run the **Mimir** PromQL checks in **Verifying metrics and logs**.
2. Confirm OTLP ingress: from a browser or `curl`, `https://otlp.tiles.symmatree.com` should be reachable on your network (401/404 is normal without a full OTLP POST; total failure to connect is a DNS or firewall issue).
3. On the NAS, confirm the Alloy container is running (Synology Container Manager) and host network is in use so it can reach the public OTLP hostnames.

### No logs in Loki

1. Run the **Loki** LogQL checks in **Verifying metrics and logs** with **`{host="raconteur"}`**.
2. Remember the **Loki** `cluster` label is **`tiles`**, not `bond`. Filter on **`host`** / **`job`** for Raconteur streams.
3. If only some jobs appear, that matches file activity (e.g. `synology-daemon` may be sparse).

### Container project missing after apply

Confirm **`deploy_synology_alloy = true`** in **`prod.tfvars`**, workspace **`prod`**, and that you applied with **`-var-file=prod.tfvars`**.
