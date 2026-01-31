# synology monitoring

raconteur.ad.local.symmatree.com (Synology) needs to be monitored.

## Architecture

Monitoring is deployed as a single Alloy container on the Synology NAS that collects:

1. **System metrics** via `prometheus.exporter.unix` (node_exporter): CPU, memory, disk I/O, network
2. **Hardware metrics** via `prometheus.exporter.snmp`: temperatures, fans, disk health, RAID status
3. **System logs** via `loki.source.file`: syslog, Synology-specific logs, auth logs

All metrics and logs are converted to OTLP format and forwarded to both tiles-test and tiles clusters via OTLP HTTP endpoints (`https://otlp.{cluster}.symmatree.com`) with consistent labeling from a single collection point (no separate SNMP exporter needed in cluster).

The OTLP endpoints are exposed via ingress and route to the `alloy-alloy-receiver` service (port 4318) in each cluster's `alloy` namespace. See [`charts/argocd-applications/templates/alloy-application.yaml`](../charts/argocd-applications/templates/alloy-application.yaml) for the ingress configuration.

## Raconteur Setup

SNMP v3 is enabled on the Synology. Credentials are stored in 1Password at `op://tiles-secrets/raconteur-snmp`:

- `username`: SNMP v3 username
- `password`: Auth password (SHA protocol)
- `PRIVACY_PASSWORD`: Privacy password (AES protocol)

Synology configuration:

- SNMP v3 enabled (only)
- Auth Protocol: SHA
- Privacy Protocol: AES
- Device info:
  - Device name: `raconteur.ad.local.symmatree.com`
  - Device location: `bond-basement`
  - Contact: <symmetry@pobox.com>

MIB files are available at <https://global.download.synology.com/download/Document/Software/DeveloperGuide/Firmware/DSM/All/enu/Synology_MIB_File.zip>

## MIB Generation

The SNMP exporter needs both Synology-specific MIBs and standard IETF SNMP MIBs to generate a proper configuration.

### Required IETF MIBs

Your Synology documentation specifies support for these standard IETF SNMP MIBs:

- DISMAN-EVENT-MIB
  For defining event triggers and actions for network management purposes
- DISMAN-SCHEDULE-MIB
  For scheduling SNMP set operations periodically or at specific points in time
- HOST-RESOURCES-MIB
  For use in managing host systems
- IF-MIB
  For describing network interface sub-layers
- IP-FORWARD-MIB
  For the management of CIDR multipath IP Routes
- IP-MIB
  For IP and ICMP management objects
- IPV6-ICMP-MIB
  For entities implementing the ICMPv6
- IPV6-MIB
  For entities implementing the IPv6 protocol
- IPV6-TCP-MIB
  For entities implementing TCP over IPv6
- IPV6-UDP-MIB
  For entities implementing UDP over IPv6
- NET-SNMP-AGENT-MIB
  For monitoring structures for the Net-SNMP agent
- NET-SNMP-EXTEND-MIB
  For scripted extensions for the Net-SNMP agent
- NET-SNMP-VACM-MIB
  Defines Net-SNMP extensions to the standard VACM view table
- NOTIFICATION-LOG-MIB
  For logging SNMP Notifications
- SNMP-COMMUNITY-MIB
  To help support coexistence between SNMPv1, SNMPv2c, and SNMPv3
- SNMP-FRAMEWORK-MIB
  The SNMP Management Architecture MIB
- SNMP-MPD-MIB
  For Message Processing and Dispatching
- SNMP-USER-BASED-SM-MIB
  For the SNMP User-based Security Model
- SNMP-VIEW-BASED-ACM-MIB
  For the View-based Access Control Model for SNMP
- SNMPv2-MIB
  For SNMP entities
- TCP-MIB
  For managing TCP implementations
- UCD-DISKIO-MIB
  For disk IO statistics
- UCD-DLMOD-MIB
  For dynamic loadable MIB modules
- UCD-SNMP-MIB
  For private UCD SNMP MIB extensions
- UDP-MIB
  For managing UDP implementations

### Getting the MIB Files

#### Source for Standard IETF MIBs

Clone net-snmp repository and use the provided script:

```bash
# Clone net-snmp if you haven't already
git clone https://github.com/net-snmp/net-snmp.git
cd net-snmp/mibs

# Run the copy script from net-snmp/mibs directory
SNMP_EXPORTER_MIBS_DIR="/path/to/snmp_exporter/generator/mibs" /path/to/tiles/tf/nodes/templates/copy-snmp-mibs.sh
```

The script (`copy-snmp-mibs.sh`) will:

- Verify the `SNMP_EXPORTER_MIBS_DIR` environment variable is set
- Check that the directory exists
- Copy all 26 required IETF SNMP MIBs
- Exit with an error if any file is not found

#### Synology-Specific MIBs

Download the Synology MIB file from the official URL and extract it:

```bash
# Download Synology MIBs
curl -O https://global.download.synology.com/download/Document/Software/DeveloperGuide/Firmware/DSM/All/enu/Synology_MIB_File.zip

# Extract into snmp_exporter generator mibs directory
unzip Synology_MIB_File.zip -d snmp_exporter/generator/mibs/
```

### Generate the snmp.yml Config

The `snmp_exporter` generator tool parses your MIBs and creates a config that maps OIDs to Prometheus metrics. Use 1Password CLI to inject your credentials into the generator config.

#### Prerequisites

Install the net-snmp development headers (required to build the generator):

```bash
sudo apt-get install libsnmp-dev
```

#### Run the generator

A template file `generator.yml.tpl` is provided with secret references to your 1Password item.

Inject secrets and run the generator:

```bash
# Set these to your actual paths
TILES_DIR="/path/to/tiles"
SNMP_EXPORTER_DIR="/path/to/snmp_exporter"

cd $SNMP_EXPORTER_DIR/generator

# Inject 1Password secrets directly into the generator directory (temporary)
op inject -i $TILES_DIR/tf/nodes/templates/generator.yml -o ./generator.yml

# Run the generator (outputs to snmp.yml in current directory)
go run . generate -m ./mibs

# Clean up the temporary generator.yml with embedded secrets
rm ./generator.yml

# Move the generated config to tiles
mv snmp.yml $TILES_DIR/tf/nodes/templates/snmp-synology-raw.yml
```

Now edit snmp.yml to replace the hard-coded auth with variable templates
for terraform to replace again later. Then delete the snmp.yml.

This generates a `snmp.yml` that defines which OIDs from your MIBs will be queried, with your SNMPv3 credentials securely injected from 1Password. The temporary `generator.yml` with embedded secrets is deleted immediately after.

The confident text above was written by an LLM that didn't seem to understand that
the auth info was also embedded in the generated file (but we can pull it back out
and make it a template as well.)

## Implementation Details

### Files

- **[tf/nodes/synology-alloy.tf](../tf/nodes/synology-alloy.tf)**: Terraform for the Alloy container project on Synology
  - Fetches SNMP credentials from 1Password
  - Mounts Alloy and SNMP configs
  - Configures host networking and PID mode for metrics collection
  - Configures OTLP endpoints: `https://otlp.tiles-test.symmatree.com` and `https://otlp.tiles.symmatree.com`

- **[tf/nodes/templates/alloy-synology.alloy](../tf/nodes/templates/alloy-synology.alloy)**: Alloy configuration
  - `prometheus.exporter.unix`: System metrics via node_exporter
  - `prometheus.exporter.snmp`: Hardware metrics via SNMP (temperatures, fans, disk health)
  - `loki.source.file`: Log collection from /var/log
  - Converts all to OTLP format and forwards to tiles-test and tiles clusters

- **[tf/nodes/templates/snmp-synology.yml](../tf/nodes/templates/snmp-synology.yml)**: SNMP exporter configuration
  - Defines Synology OID module (1.3.6.1.4.1.6574.*)
  - Configured for SNMPv3 with authentication and privacy
  - Template variables for passwords injected from 1Password

### Metrics Available

**Hardware sensors (via SNMP):**

- Temperature sensors (CPU, system, disks)
- Fan speeds and states
- Power supply status
- Disk health indicators
- RAID pool health
- Volume metrics

**System metrics (via node_exporter):**

- CPU utilization and load
- Memory and swap
- Disk I/O
- Network interface stats
- Process counts

**Logs:**

- System syslog (/var/log/messages)
- Synology application logs (/var/log/synolog/)
- Authentication logs (/var/log/auth.log)
- Daemon logs (/var/log/daemon.log)

## Troubleshooting

### SNMP Scrape Failures

When you see errors like `Failed to scrape Prometheus endpoint` for the SNMP exporter:

1. **Check Alloy component health**:
   - Container uses host networking (`network_mode = "host"`), so Alloy UI is accessible at `https://raconteur.ad.local.symmatree.com:5001/` (or the Synology's IP address)
   - The UI shows component status, including `prometheus.exporter.snmp.synology` health and any errors
   - View container logs from Synology Container Manager for detailed error messages
   - If the SNMP exporter component shows as unhealthy or not running in the UI, check:
     - Component configuration errors (red status in UI)
     - SNMP config file path and permissions
     - SNMP exporter component logs in the UI's component detail view

2. **Verify SNMP connection**: Test SNMP connectivity directly:
   - TODO: Determine if `docker exec` or Synology Container Manager provides shell access to the container
   - TODO: Once access method is known, document the command:

     ```bash
     snmpwalk -v3 -l authPriv -u <username> -a SHA -A <auth_password> -x AES -X <privacy_password> 127.0.0.1:161 1.3.6.1.4.1.6574.1
     ```

   - Credentials are in 1Password at `op://tiles-secrets/raconteur-snmp`

3. **Check SNMP config file**: Verify the config file is mounted correctly and auth is referenced:
   - The `synology` module in `snmp-synology.yml` references `auth: synology_v3` to use the SNMPv3 credentials
   - Verify template variables were replaced correctly (check for `${snmp_username}` placeholders in the mounted file)
   - The config is mounted at `/etc/snmp_exporter/snmp.yml` in the container

4. **Enable debug logging**: Add debug logging to Alloy by setting environment variable in `synology-alloy.tf`:

   ```hcl
   environment = {
     HOSTNAME = "raconteur"
     ALLOY_LOG_LEVEL = "debug"
   }
   ```

   Then redeploy the container project.

5. **Check SNMP exporter component**: The SNMP exporter is embedded in Alloy (not a separate service). The `prometheus.exporter.snmp.synology` component exposes targets that are scraped by `prometheus.scrape "snmp"`. Check Alloy logs for SNMP-specific errors.

6. **Verify SNMP service on Synology**: SNMP v3 is configured on the Synology (see "Raconteur Setup" section). Verify it's listening:
   - TODO: Determine if SSH access to Synology host is available
   - TODO: If SSH available, document: `netstat -tuln | grep 161`
   - Otherwise check: Synology Control Panel > Terminal & SNMP > SNMP tab

7. **Check Alloy component status**:
   - Alloy web UI is accessible at `https://raconteur.ad.local.symmatree.com:5001/`
   - Component details are available at URLs like `http://raconteur.ad.local.symmatree.com:12345/component/otelcol.exporter.otlphttp.tiles`
   - To view the SNMP exporter component status, navigate to `http://raconteur.ad.local.symmatree.com:12345/component/prometheus.exporter.snmp.synology`
   - Otherwise, check container logs for component health messages
