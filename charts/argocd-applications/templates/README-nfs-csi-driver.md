# NFS CSI Driver

## Overview

The [NFS CSI Driver](https://github.com/kubernetes-csi/csi-driver-nfs) provides a Container Storage Interface (CSI) driver for mounting NFS shares as Kubernetes persistent volumes. It enables workloads to use NFS storage for persistent volumes, supporting both ReadWriteOnce (RWO) and ReadWriteMany (RWX) access modes.

This driver is critical infrastructure for the cluster, providing shared storage for observability components (Loki, Mimir) and application services (ODM) that require shared filesystem access.

## Architecture

The NFS CSI Driver is deployed as a Helm chart with the following components:

- **CSI Driver**: Handles volume provisioning, mounting, and unmounting
- **Storage Class**: `cluster-nfs` - Defines how NFS volumes are provisioned
- **Node Plugin**: Runs on each node to handle volume mounts

### Storage Class Configuration

- **Name**: `cluster-nfs`
- **Server**: NFS server hostname/IP (provided via `nfs_server` value)
- **Share**: NFS share path (provided via `cluster_nfs_path` value)
- **Reclaim Policy**: `Delete` - Dynamically provisioned volumes are deleted when PVCs are deleted
- **Volume Binding Mode**: `WaitForFirstConsumer` - Volume is bound when a pod using it is scheduled
- **Mount Options**: `vers=4.1` - Uses NFSv4.1 protocol with built-in locking

### Storage Use Cases

This cluster uses NFS storage for three distinct use cases:

1. **Cluster-internal persistent data**: Data that must persist across cluster recreation, stored under the cluster-specific shared volume (`tiles` or `tiles-test`) with app-specific subdirectories (e.g., `mimir-data`, `loki-data`). Uses static PVs with fixed paths.

2. **External shared data**: Data that should be accessible from outside the cluster, using explicit NFS paths (e.g., the `datasets` shared folder containing bulk data like imagesets from collection flights). Uses static PVs with explicit paths.

3. **PVC-level storage** (potential future use): Semi-disposable storage that needs ReadWriteMany access or must not be node-locked (unlike LocalPathProvisioner). Would use dynamic provisioning via the `cluster-nfs` storage class.

See [`docs/nfs-storage-architecture.md`](../../../docs/nfs-storage-architecture.md) for details on the static PV strategy and why it's used for critical workloads.

## Configuration

### Key Configuration Values

Configuration is managed through the Application's `valuesObject`. These values are passed from Terraform via the bootstrap process and stored in the 1Password `{cluster_name}-misc-config` secret:

- **NFS Server**: `nfs_server` - Hostname or IP of the NFS server (Synology NAS)
- **Cluster NFS Path**: `cluster_nfs_path` - NFS share path for cluster-internal persistent data (e.g., `/volume2/tiles`)
- **Datasets NFS Path**: `datasets_nfs_path` - NFS share path for external shared data (e.g., `/volume2/datasets`)
- **Enable Snapshotter**: `false` - Volume snapshots are not enabled. Note: The snapshotter is an external snapshotter that copies data (not a filesystem-level snapshot feature like ZFS or Btrfs snapshots).
- **Storage Class Name**: `cluster-nfs`

These values can be examined in the 1Password `{cluster_name}-misc-config` item's `config` section.

### Environment-Specific Settings

- NFS server and paths are cluster-specific and set via Terraform/bootstrap process
- Values are stored in 1Password `{cluster_name}-misc-config` secret and can be examined there
- Production cluster typically uses `/volume2/tiles` for `cluster_nfs_path`
- Test cluster typically uses `/volume2/tiles-test` for `cluster_nfs_path`
- `datasets_nfs_path` is typically `/volume2/datasets` (shared across clusters)

### Dependencies

- **NFS Server**: Synology NAS must be configured with appropriate NFS shares and access rules
- **Network**: Cluster nodes must have network connectivity to the NFS server

## Prerequisites

### Required Infrastructure

- **NFS Server**: Synology NAS with NFS service enabled
- **NFS Shares**: Must be created on the NAS before deploying (see [`docs/nfs-storage-architecture.md`](../../../docs/nfs-storage-architecture.md) for setup instructions)
- **NFS Access Rules**: CIDR-based access control rules must be configured on the NAS
- **Network**: Cluster nodes must be able to reach the NFS server

### Required Values

- `nfs_server`: NFS server hostname/IP
- `cluster_nfs_path`: NFS share path for cluster storage

## Terraform Integration

N/A - NFS CSI Driver does not have Terraform-managed resources. The NFS server and shares are managed separately on the Synology NAS.

## Application Manifest

- **Application**: [`nfs-csi-driver-application.yaml`](nfs-csi-driver-application.yaml)
- **Helm Chart**: [csi-driver-nfs](https://github.com/kubernetes-csi/csi-driver-nfs/tree/master/charts) from kubernetes-csi
- **Chart Version**: `4.12.1`
- **Namespace**: `nfs-csi-driver`
- **Sync Policy**: Automated with prune and self-heal enabled
- **Sync Options**:
  - `CreateNamespace=true`
  - `ServerSideApply=true`

## Access & Endpoints

N/A - This is a storage driver with no user-facing endpoints.

## Monitoring & Observability

### Metrics

- TODO: Document if NFS CSI Driver exposes metrics

### Dashboards

N/A - No dashboards specific to this component.

### Logs

View driver logs:

```bash
# View CSI driver pods
kubectl get pods -n nfs-csi-driver

# View node plugin logs (on each node)
kubectl logs -n nfs-csi-driver -l app=csi-nfs-node

# View controller logs
kubectl logs -n nfs-csi-driver -l app=csi-nfs-controller
```

## Troubleshooting

### Common Issues

**PVCs stuck in Pending:**

- Verify storage class exists: `kubectl get storageclass cluster-nfs`
- Check that NFS server is reachable from nodes: `ping <nfs_server>` or test NFS mount manually
- Verify NFS shares exist and are accessible: Check NAS configuration
- Check CSI driver pods are running: `kubectl get pods -n nfs-csi-driver`
- Review CSI driver logs (see Logs section above)

**Volume mount failures:**

- Verify NFS server is accessible: Test network connectivity
- Check NFS access rules on NAS: Verify CIDR restrictions allow cluster node IPs
- Verify mount options are correct: Check storage class configuration
- Check node plugin logs for mount errors (see Logs section above)

**Permission denied errors:**

- Verify NFS server uses `squash_all` (all users mapped to admin)
- Check that NFS share permissions allow access
- Verify mount options don't include conflicting UID/GID mappings

**Performance issues:**

- Check network speed between cluster and NAS
- Monitor NFS server performance and disk I/O
- Verify mount options match configuration (`vers=4.1` is required for proper locking)

### Health Checks

- Verify CSI driver pods are running: `kubectl get pods -n nfs-csi-driver`
- Check storage class exists: `kubectl get storageclass cluster-nfs`
- Verify Application is synced: `kubectl get application nfs-csi-driver -n argocd`
- Test NFS connectivity: Manually mount NFS share from a node to verify access

## Maintenance

### Update Procedures

- Update the `targetRevision` in `nfs-csi-driver-application.yaml` to the desired chart version
- ArgoCD will automatically sync the changes
- Note: CSI driver updates may require node restarts or pod restarts

### Backup Requirements

NFS storage is backed up at the NAS level. Ensure the Synology NAS has appropriate backup and snapshot strategies configured. See [`docs/nfs-storage-architecture.md`](../../../docs/nfs-storage-architecture.md) for backup considerations.

### Known Limitations

- **Single point of failure**: NFS server is a single point of failure. Consider NAS HA if critical.
- **Network dependency**: All volume operations require network connectivity to the NFS server
- **Performance**: NFS performance depends on network speed and NAS performance
- **Dynamic provisioning isolation**: Dynamically provisioned volumes create isolated directories per PVC, preventing data sharing

## Storage Architecture

This cluster uses NFS storage for three use cases (see Architecture section above):

1. **Cluster-internal persistent data** (Loki, Mimir): Static PVs with fixed paths under `cluster_nfs_path` (e.g., `/volume2/tiles/mimir-data`)
2. **External shared data** (ODM): Static PVs with explicit paths (e.g., `/volume2/datasets/webodm-media-{cluster_name}`)
3. **PVC-level storage** (future): Dynamic PVs via `cluster-nfs` storage class for semi-disposable RWX storage

See [`docs/nfs-storage-architecture.md`](../../../docs/nfs-storage-architecture.md) for detailed documentation on:

- Why NFS is used (shared filesystem requirements)
- Static PV strategy and fixed paths
- NFS configuration and mount options
- Synology NAS setup requirements
- Performance and reliability considerations

## NFS Server Setup

The NFS server (Synology NAS) must be configured before deploying workloads that use NFS storage:

1. **Create NFS Shares**: Create shared folders on the NAS (see architecture doc for specific paths)
2. **Configure NFS Rules**: Set up CIDR-based access control for cluster node IPs
3. **Set Security Settings**: Use NFSv4.1 with `sys` security and `squash_all` user mapping

See [`docs/nfs-storage-architecture.md`](../../../docs/nfs-storage-architecture.md) for complete setup instructions.
