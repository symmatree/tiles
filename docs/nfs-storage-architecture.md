# NFS Storage Architecture

## NFS CSI Driver Behavior

The NFS CSI driver creates a **unique directory per PVC** under the NFS share root. For example:

- Share: `/tiles-nfs`
- PVC `mimir-shared-storage` → `/tiles-nfs/pvc-1234/`
- PVC `loki-storage` → `/tiles-nfs/pvc-5678/`

Each PVC gets its own isolated directory, preventing conflicts but also preventing data sharing unless explicitly configured.

## Why NFS (Shared Filesystem Required)

Loki and Mimir require a shared filesystem that supports ReadWriteMany (RWX) access mode because multiple components (ingesters, compactors, queriers, store-gateways) must concurrently mount and access the same data directories. NFS is chosen over SMB because SMB has known issues with memory leaks and OOM conditions that can cause Kubernetes nodes to become unreachable when mounts consume excessive memory.

## Storage Strategy

All services use **static PVs with fixed paths** to ensure persistence across ArgoCD Application deletion/recreation. This allows data to survive Application deletion since the PV persists independently.

### Static PVs

- **Static PV** with fixed path under cluster-specific NFS shares
- **PVC bound to that PV** (not dynamically provisioned)
- **Reclaim policy: Retain** - PVs persist even if PVCs are deleted
- Used by:
  - **Loki**: `/volume2/{cluster_name}/loki-data` (e.g., `/volume2/tiles/loki-data` for prod, `/volume2/tiles-test/loki-data` for test)
  - **Mimir**: `/volume2/{cluster_name}/mimir-data` (e.g., `/volume2/tiles/mimir-data` for prod, `/volume2/tiles-test/mimir-data` for test)
  - **ODM**: `/volume2/datasets/webodm-media-{cluster_name}` (with subpath mount for isolation)

## NFS Configuration

### Mount Options

Storage classes use NFSv4.1 with built-in locking (no `rpc.statd` required):

- `vers=4.1` - NFSv4.1 protocol
- Server uses `squash_all` - all users mapped to admin user on NAS
- No UID mapping mount options needed since server handles user mapping

### Synology NFS Setup

**NFS Export Path:**

- Synology exports shared folders with the volume name as part of the path
- If you create a shared folder named `tiles` on volume `volume2`, Synology exports it as `/volume2/tiles`
- The NFS path in configuration must include the volume name (e.g., `/volume2/tiles`)
- Subdirectories like `loki-data` and `mimir-data` are created under the share root

**Security:**

- Use NFSv4.1 with `sys` security
- Server uses `squash_all` - all users mapped to admin user on NAS (no UID mapping needed)
- **Primary security is CIDR-based access control** - restrict NFS access to cluster node IPs via NFS rules (not `*`)
- Since all users are squashed to admin, authentication is effectively bypassed; access control relies entirely on the CIDR restrictions in NFS rules

## Manual NFS Setup

The following NFS shares and rules must be created on the Synology NAS before deploying applications:

### Required NFS Shares

Create the following shared folders on the NAS:

- **Production cluster:**
  - `tiles` (on volume2) → exports as `/volume2/tiles`
    - Subdirectories `loki-data` and `mimir-data` will be created automatically by the applications
- **Test cluster:**
  - `tiles-test` (on volume2) → exports as `/volume2/tiles-test`
    - Subdirectories `loki-data` and `mimir-data` will be created automatically by the applications
- **Both clusters:**
  - `datasets` (on volume2) → exports as `/volume2/datasets` (pre-existing, used by ODM)

### NFS Rules Configuration

For each shared folder, create an NFS rule with the following settings:

**For `tiles` (production):**

- **Hostname/IP (CIDR)**: `10.0.128.0/18` (covers entire prod cluster allocation: nodes, pods, services, external IPs - 10.0.128.0 to 10.0.191.255)
- **Privilege**: Read/Write
- **Squash**: Map all users to admin
- **Security**: `sys`
- **Enable asynchronous**: ✓ Checked
- **Allow connections from non-privileged ports**: ✓ Checked
- **Allow users to access mounted subfolders**: ✓ Checked

**For `tiles-test` (test):**

- **Hostname/IP (CIDR)**: `10.0.192.0/18` (covers entire test cluster allocation: nodes, pods, services, external IPs - 10.0.192.0 to 10.0.255.255)
- All other settings same as above

**For `datasets` (both clusters):**

- **Hostname/IP (CIDR)**: `10.0.128.0/17` (union CIDR covering both prod and test clusters: 10.0.128.0-10.0.255.255)
- All other settings same as above

**Note:** Once NFS rules are created, access is restricted to only the IPs/CIDRs specified in the rules. If no rules are configured, Synology may allow or deny access by default depending on the NFS service settings.

## Performance and Reliability

- **Performance:** NFS performance depends on network speed between cluster and NAS. Consider 10G network if available. Monitor I/O performance.
- **High Availability:** NFS is a single point of failure. Consider NAS HA if critical. Document recovery procedures.
- **Backup:** Ensure NAS has backup strategy. Consider snapshot schedules on NAS. Document recovery procedures.
