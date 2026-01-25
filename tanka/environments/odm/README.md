# ODM (OpenDroneMap)

## Overview

[OpenDroneMap](https://github.com/OpenDroneMap/WebODM) is a photogrammetry application for processing drone imagery into 3D models, point clouds, and orthomosaics. It provides a web interface for uploading images, configuring processing parameters, and viewing results.

ODM is deployed using Tanka/Jsonnet and consists of multiple components working together to process drone imagery.

## Architecture

ODM is deployed as a multi-component application:

- **WebODM Web App**: Main web interface and API server
- **WebODM Worker**: Background worker for processing tasks
- **NodeODM**: Processing engine that performs the actual photogrammetry work
- **PostgreSQL with PostGIS**: Database for storing project metadata and geospatial data
- **Redis**: Message broker for task queue management

### Storage Architecture

ODM uses a hybrid storage approach:

- **PostgreSQL Storage**: Uses local-path storage (10Gi PVC) for database files
- **Media Storage**: Uses NFS static PV with fixed path for project media files
  - Static PV path: `{datasets_nfs_path}/webodm-media-{cluster_name}` (e.g., `/volume2/datasets/webodm-media-tiles`)
  - Mounted at `/webodm/app/media` with subpath `webodm-media` for isolation
  - PV size: 100Gi

See [`docs/nfs-storage-architecture.md`](../../../docs/nfs-storage-architecture.md) for detailed information on the NFS storage strategy.

### NodeODM Configuration

NodeODM runs with dedicated node tolerations (`dedicated=nodeodm`) and has cluster-specific memory limits:

- **Production cluster**: 6Gi memory
- **Test cluster**: 1Gi memory

## Configuration

### Key Configuration Values

Configuration is managed through the Application's plugin parameters:

- **WebODM Ingress Host**: `odm.{cluster_name}.symmatree.com`
- **NFS Server**: `nfs_server` - NFS server hostname/IP
- **Datasets NFS Path**: `datasets_nfs_path` - NFS share path for datasets (e.g., `/volume2/datasets`)

### Environment-Specific Settings

- Cluster name, NFS server, and datasets NFS path are cluster-specific and set via Terraform/bootstrap process
- NodeODM memory limits vary by cluster (production: 6Gi, test: 1Gi)

### Dependencies

- **[cert-manager](../../../charts/cert-manager/README.md)**: Required for TLS certificates
- **[external-dns](../../../charts/external-dns/README.md)**: Required for DNS record creation
- **[Cilium](../../../charts/cilium/README.md)**: Provides ingress controller
- **[NFS CSI Driver](../../../charts/argocd-applications/templates/README-nfs-csi-driver.md)**: Required for NFS storage (though this uses static PV)
- **[Local Path Provisioner](../../../charts/argocd-applications/templates/README-local-path-provisioner.md)**: Used for PostgreSQL storage

## Prerequisites

### Required Infrastructure

- **NFS Share**: `{datasets_nfs_path}/webodm-media-{cluster_name}` must exist on the NFS server
  - Created automatically by ODM or must be pre-created
  - See [`docs/nfs-storage-architecture.md`](../../../docs/nfs-storage-architecture.md) for setup details
- **Dedicated Node**: NodeODM requires nodes with `dedicated=nodeodm` taint (optional, but recommended for GPU acceleration)

### Required Values

- `cluster_name`: Cluster identifier
- `nfs_server`: NFS server hostname/IP
- `datasets_nfs_path`: NFS share path for datasets

## Terraform Integration

N/A - ODM does not have Terraform-managed resources.

## Application Manifest

- **Application**: [`application.yaml`](application.yaml)
- **Tanka Environment**: `tanka/environments/odm/`
- **Main Jsonnet**: [`main.jsonnet`](main.jsonnet)
- **Namespace**: `odm`
- **Sync Policy**: Automated with prune and self-heal enabled
- **Sync Options**:
  - `CreateNamespace=true`
  - `ServerSideApply=true`

## Access & Endpoints

### Web UI

- **URL**: `https://odm.{cluster_name}.symmatree.com`
- **TLS**: Managed by cert-manager using `real-cert` ClusterIssuer
- **Authentication**: Default WebODM authentication (configured via web UI)

## Monitoring & Observability

### Metrics

- TODO: Document if ODM exposes metrics

### Dashboards

- TODO: Document if ODM has dashboards

### Logs

View ODM component logs:

```bash
# WebODM web app logs
kubectl logs -n odm -l app=webodm

# WebODM worker logs
kubectl logs -n odm -l app=webodm -c webodm-worker

# NodeODM logs
kubectl logs -n odm -l app=nodeodm

# PostgreSQL logs
kubectl logs -n odm -l name=postgres

# Redis broker logs
kubectl logs -n odm -l name=redis-broker
```

## Troubleshooting

### Common Issues

**WebODM not accessible:**

- Verify ingress is created: `kubectl get ingress -n odm`
- Check certificate status: `kubectl get certificate -n odm`
- Verify external-dns created DNS record
- Check WebODM pod is running: `kubectl get pods -n odm -l app=webodm`

**Processing jobs not starting:**

- Verify NodeODM is running: `kubectl get pods -n odm -l app=nodeodm`
- Check NodeODM is registered: Check WebODM UI → Settings → Processing Nodes
- Verify Redis broker is running: `kubectl get pods -n odm -l name=redis-broker`
- Check worker logs for errors (see Logs section above)

**Storage issues:**

- Verify NFS PV is mounted: `kubectl exec -n odm <webodm-pod> -- ls -la /webodm/app/media`
- Check NFS server connectivity and permissions
- Verify PostgreSQL PVC is bound: `kubectl get pvc odm-postgres -n odm`
- Check PostgreSQL pod is running: `kubectl get pods -n odm -l name=postgres`

**Database connection errors:**

- Verify PostgreSQL is running: `kubectl get pods -n odm -l name=postgres`
- Check PostgreSQL logs for errors (see Logs section above)
- Verify PostGIS extension is installed: Check init scripts ConfigMap

**NodeODM not registering:**

- Check NodeODM service is accessible: `kubectl get svc -n odm`
- Verify NodeODM pod is running: `kubectl get pods -n odm -l app=nodeodm`
- Check WebODM postStart hook logs for registration errors
- Manually register NodeODM if needed via WebODM UI

### Health Checks

- Verify all pods are running: `kubectl get pods -n odm`
- Check Application is synced: `kubectl get application odm -n argocd`
- Test web UI access: Navigate to `https://odm.{cluster_name}.symmatree.com`
- Verify NodeODM is registered: Check WebODM UI → Settings → Processing Nodes

## Maintenance

### Update Procedures

- Update container image versions in `main.jsonnet`
- ArgoCD will automatically sync changes
- Note: ODM updates may require pod restarts and may cause brief downtime

### Backup Requirements

- **PostgreSQL Database**: Stored in local-path PVC, should be backed up if projects need to be preserved
- **Media Files**: Stored on NFS, backed up at NAS level
- **Configuration**: Stored in Git (main.jsonnet), backed up there

### Known Limitations

- **Single Instance**: ODM runs as a single instance (no HA)
- **NodeODM Memory**: Memory limits are cluster-specific and may need adjustment based on workload
- **GPU Acceleration**: GPU acceleration requires appropriate node configuration and may work better with WSL integration on Windows

## Usage

### Processing Workflow

1. Navigate to `https://odm.{cluster_name}.symmatree.com`
2. Create a new project
3. Upload drone imagery
4. Configure processing parameters
5. Start processing job
6. NodeODM processes the images
7. View results (3D models, point clouds, orthomosaics) in the web UI

### NodeODM Registration

NodeODM is automatically registered via a postStart hook in the WebODM container. If registration fails, it can be manually registered via the WebODM UI at Settings → Processing Nodes.

### Storage Management

Media files are stored on NFS at `{datasets_nfs_path}/webodm-media-{cluster_name}`. Monitor disk usage on the NFS server to ensure adequate space for processed projects.

See [`docs/nfs-storage-architecture.md`](../../../docs/nfs-storage-architecture.md) for detailed information on NFS storage setup and management.
