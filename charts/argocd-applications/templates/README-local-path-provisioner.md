# Local Path Provisioner

## Overview

[Local Path Provisioner](https://github.com/rancher/local-path-provisioner) is a dynamic storage provisioner that creates persistent volumes using local node storage paths. It provides simple local storage for workloads that don't require shared storage or high availability.

The provisioner creates a StorageClass named `local-path` that is set as the default storage class for the cluster, making it easy to provision local storage without explicitly specifying a storage class.

## Architecture

Local Path Provisioner runs as a DaemonSet on each node and provisions PersistentVolumes using local filesystem paths on the node where the pod is scheduled. Each volume is bound to a specific node and cannot be moved to another node.

### Storage Class Configuration

- **Name**: `local-path`
- **Default Class**: Yes (set as cluster default)
- **Reclaim Policy**: `Delete` - volumes are deleted when PVCs are deleted
- **Volume Binding Mode**: `WaitForFirstConsumer` - volume is not bound until a pod using it is scheduled, allowing the scheduler to choose the appropriate node

## Configuration

### Key Configuration Values

Configuration is managed through the Application's `valuesObject`:

- **Storage Class Name**: `local-path`
- **Default Class**: `true` - set as the default storage class
- **Reclaim Policy**: `Delete`
- **Volume Binding Mode**: `WaitForFirstConsumer`

### Environment-Specific Settings

No environment-specific configuration needed - the storage class works the same across all clusters.

### Dependencies

None - Local Path Provisioner is a standalone component.

## Prerequisites

- **Kubernetes cluster**: With nodes that have local storage available
- **Node storage**: Sufficient local disk space on nodes for volumes

## Terraform Integration

N/A - Local Path Provisioner does not have Terraform-managed resources.

## Application Manifest

- **Application**: [`local-path-provisioner-application.yaml`](local-path-provisioner-application.yaml)
- **Helm Chart**: [local-path-provisioner](https://charts.containeroo.ch) from containeroo.ch
- **Chart Version**: `0.0.32`
- **Namespace**: `local-path-provisioner`
- **Sync Policy**: Automated with prune and self-heal enabled
- **Sync Options**:
  - `CreateNamespace=true`
  - `ServerSideApply=true`

## Access & Endpoints

N/A - This is a storage provisioner with no user-facing endpoints.

## Monitoring & Observability

### Metrics

- TODO: Document if Local Path Provisioner exposes metrics

### Dashboards

N/A - No dashboards specific to this component.

### Logs

View provisioner logs:

```bash
# View DaemonSet pods
kubectl get pods -n local-path-provisioner

# View provisioner logs (on each node)
kubectl logs -n local-path-provisioner -l app=local-path-provisioner
```

## Troubleshooting

### Common Issues

**PVCs stuck in Pending:**

- Verify storage class exists: `kubectl get storageclass local-path`
- Check that storage class is default: `kubectl get storageclass local-path -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}'`
- Verify pods are scheduled: `kubectl get pods -n local-path-provisioner`
- Check node disk space: `kubectl describe node <node-name>`

**Volumes not being created:**

- Check provisioner logs (see Logs section above)
- Verify PVC is using the correct storage class: `kubectl get pvc -o yaml`
- Check that a pod using the PVC is scheduled (WaitForFirstConsumer requires this)

**Data loss after pod/node restart:**

- This is expected behavior - local-path volumes are node-local and not replicated
- Data persists on the node filesystem, but if the node is lost, the data is lost
- Use NFS or other shared storage for workloads that require data durability

### Health Checks

- Verify DaemonSet pods are running on all nodes: `kubectl get pods -n local-path-provisioner`
- Check storage class exists and is default: `kubectl get storageclass local-path`
- Verify Application is synced: `kubectl get application local-path-provisioner -n argocd`

## Maintenance

### Update Procedures

- Update the `targetRevision` in `local-path-provisioner-application.yaml` to the desired chart version
- ArgoCD will automatically sync the changes

### Backup Requirements

Local-path volumes are stored on node filesystems and are not backed up. Workloads using local-path storage should not contain critical data that requires backup. For data that needs backup, use NFS or other shared storage solutions.

### Known Limitations

- **Node-local only**: Volumes cannot be moved between nodes
- **No replication**: Data is stored on a single node with no redundancy
- **Node failure**: If a node fails, volumes on that node are lost
- **Not suitable for stateful workloads**: Use NFS or other shared storage for workloads requiring data durability or multi-node access

## Usage

### When to Use Local Path Storage

Local-path storage is suitable for:

- Temporary or cache data
- Workloads that can tolerate data loss
- Single-pod workloads that don't need shared access
- Development/testing environments

### When NOT to Use Local Path Storage

Do not use local-path storage for:

- Critical application data
- Workloads requiring shared access (ReadWriteMany)
- Stateful workloads that need data durability
- Production databases or important state

### Example Usage

Workloads that use local-path storage in this cluster:

- **Loki**: Uses local-path for the singleBinary pod's local persistence (StatefulSet PVC). The actual data storage uses NFS via a static PV mounted as an extra volume.
- **ODM**: Uses local-path for the PostgreSQL database PVC (10Gi). The main ODM data storage uses NFS.

Most workloads requiring persistent storage use NFS (via the `cluster-nfs` storage class) for shared access and data durability. Local-path is used for node-local storage needs like local caches or single-pod databases.
