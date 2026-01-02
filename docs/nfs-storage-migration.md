# Migration Plan: GCS to NFS Storage for Loki and Mimir

## Overview

This document outlines the plan to migrate Loki and Mimir from Google Cloud Storage (GCS) to NFS storage on the Synology NAS (raconteur). This migration eliminates GCS egress costs (~$120/month) by moving all storage operations on-prem.

**Key Assumptions:**

- All existing data in GCS can be discarded (fresh start)
- NFS authentication will use credentials stored in 1Password
- Migration will be done during a maintenance window

## Goals

1. Eliminate GCS egress costs by moving storage on-prem
2. Maintain functionality of Loki and Mimir
3. Use NFS storage class for persistent volumes
4. Store NFS credentials securely in 1Password

## Why NFS (Shared Filesystem Required)

Loki and Mimir require a shared filesystem that supports ReadWriteMany (RWX) access mode because multiple components (ingesters, compactors, queriers, store-gateways) must concurrently mount and access the same data directories. NFS is chosen over SMB because SMB has known issues with memory leaks and OOM conditions that can cause Kubernetes nodes to become unreachable when mounts consume excessive memory.

## Prerequisites

### 1. Synology NFS Setup

On the Synology NAS (raconteur.ad.local.symmatree.com):

1. **Enable NFS Service:**
   - DSM → Control Panel → File Services → NFS
   - Enable NFS v4.1 or higher
   - **Note on Kerberos:** Kerberos authentication (krb5) is optional but heavyweight - it requires a Key Distribution Center (KDC), service principals, keytab files, and client configuration on all Kubernetes nodes. For a trusted on-prem network, standard NFS with `sys` security (user ID-based) is typically sufficient and much simpler. Kerberos is mainly useful for untrusted networks or strict compliance requirements.

2. **Create Shared Folders:**
   - Create shared folder: `tiles-loki` (will be at `/volume1/tiles-loki` or appropriate volume on the filesystem)
   - Create shared folder: `tiles-test-loki` (will be at `/volume1/tiles-test-loki` or appropriate volume on the filesystem)
   - Create shared folder: `tiles-mimir` (will be at `/volume1/tiles-mimir` or appropriate volume on the filesystem)
   - Create shared folder: `tiles-test-mimir` (will be at `/volume1/tiles-test-mimir` or appropriate volume on the filesystem)
   - **Important:** The NFS export path will be just the share name (e.g., `/tiles-loki`), not the full volume path. The shared folder name is what gets exported via NFS.

3. **Create Separate NAS User Accounts:**
   - Create user: `tiles-loki-sa` (for Loki storage access)
   - Create user: `tiles-mimir-sa` (for Mimir storage access)
   - These are regular NAS user accounts (not special "NFS accounts")
   - Set strong passwords for each user
   - **Important:** Do NOT grant these users access to other shares - they should only access their respective storage folders
   - Note: NFS does NOT require anonymous access (unlike SMB) - all access is authenticated via these user accounts
   - Note: "Authenticated" means "tell me that  your uid number is 1026 or whatever and you're in", the password is NOT used.

4. **Configure Folder Permissions (File Station or Control Panel):**
   - For `/volume1/tiles-loki`:
     - Grant `tiles-loki` user: Read/Write permissions
     - Do NOT grant `tiles-mimir` user any access
   - For `/volume1/tiles-mimir`:
     - Grant `tiles-mimir` user: Read/Write permissions
     - Do NOT grant `tiles-loki` user any access
   - This ensures each service can only access its own storage

5. **Configure NFS Permissions (File Services → NFS):**

   **Get Cluster Node IPs:**

   The node IPs are defined in your Terraform configuration. Extract them using one of these methods:

   ```bash
   # Method 1: Extract from tfvars file (workspace-specific)
   cd tf/nodes
   # For prod workspace:
   grep -E "ip_address\s*=" prod.auto.tfvars | sed 's/.*ip_address.*=.*"\(.*\)".*/\1/' | sort -u
   # For test workspace:
   grep -E "ip_address\s*=" test.auto.tfvars | sed 's/.*ip_address.*=.*"\(.*\)".*/\1/' | sort -u

   # Method 2: Extract all IPs from any tfvars (if using a single file)
   grep -E "ip_address\s*=" *.tfvars | sed 's/.*ip_address.*=.*"\(.*\)".*/\1/' | sort -u

   # Method 3: Use terraform output (recommended - available after terraform apply)
   terraform output -json all_node_ips | jq -r '.[]' | tr '\n' ','
   # Or for space-separated list:
   terraform output -json all_node_ips | jq -r '.[]' | tr '\n' ' '
   ```

   **Configure NFS Rules:**

   For each folder, create an NFS rule with the following settings. Note: Once NFS rules are created, access is typically restricted to only the IPs/CIDRs specified in the rules.

   - **Folder:** Select the shared folder `tiles-loki` (prod) or `tiles-test-loki` (test) from the dropdown
     - Click "Create" to add a new NFS rule
     - **Hostname/IP (CIDR)**: Use one of these options:
       - **Option 1 (Recommended)**: Single CIDR covering both clusters: `10.0.128.0/17`
         - This covers both prod (10.0.128.x) and test (10.0.192.x) cluster nodes
       - **Option 2**: Separate CIDRs per cluster:
         - For prod folders: `10.0.128.0/24` (covers 10.0.128.11-13, 10.0.128.21-23)
         - For test folders: `10.0.192.0/24` (covers 10.0.192.11, 10.0.192.21)
     - **Privilege**: Read/Write
     - **Squash**: Map all users to admin (simplifies access, no UID mapping needed)
     - **Security**: `sys` (standard user ID-based authentication)
     - **Enable asynchronous**: ✓ Checked (improves performance)
     - **Allow connections from non-privileged ports**: ✓ Checked (required for Kubernetes pods)
     - **Allow users to access mounted subfolders**: ✓ Checked (needed for nested directories)

   - **Folder:** Select the shared folder `tiles-mimir` (prod) or `tiles-test-mimir` (test) from the dropdown
     - Create a separate NFS rule with the same settings as above
     - **Hostname/IP (CIDR)**: Use the same CIDR(s) as configured for the Loki folders above

   **User Restriction (Folder Permissions):**

   User access restriction is configured separately via folder permissions (not in the NFS rule):
   - For shared folder `tiles-loki`: Grant `tiles-loki-sa` user Read/Write permissions, do NOT grant `tiles-mimir-sa` any access
   - For shared folder `tiles-mimir`: Grant `tiles-mimir-sa` user Read/Write permissions, do NOT grant `tiles-loki-sa` any access
   - This ensures each service can only access its own storage folder

   **Note on NFS Export Path:**
   - Synology exports shared folders by their share name, not the full volume path
   - If you create a shared folder named `tiles-loki`, Synology will export it as `/tiles-loki` (not `/volume1/tiles-loki`)
   - The NFS path in your Terraform configuration should match the export path: `/tiles-loki`, `/tiles-test-loki`, `/tiles-mimir`, `/tiles-test-mimir`

   **Note:**
   - NFS rules restrict access by IP/CIDR - only your cluster nodes will be able to mount these shares
   - Folder permissions restrict access by user - each service account can only access its designated folder
   - The combination of IP restriction (NFS rules) and user restriction (folder permissions) provides defense in depth
   - The node IPs are available in your Terraform plan/apply output, so you can verify them during the daily validation runs

### UID Mapping Configuration

With NFSv4.1 and `squash_all` configured on the server, all users are mapped to the admin user on the NAS. This simplifies the setup by eliminating the need for UID mapping configuration.

**StorageClass Mount Options:**

The storage class configuration is defined in `charts/argocd-applications/templates/nfs-csi-driver-application.yaml`. It configures two storage classes (`nfs-loki` and `nfs-mimir`) that use NFSv4.1 with built-in locking (no `rpc.statd` required). No UID mapping mount options are needed since the server handles all user mapping via `squash_all`.

**Note on Value Propagation:**

The NFS configuration values (`loki_nfs_path`, `mimir_nfs_path`, and `nfs_server`) are stored in the `{cluster}-misc-config` 1Password item. These values propagate from Terraform → 1Password → GitHub Actions workflow → ArgoCD → Helm, where they're used in the NFS CSI driver application template.

## Terraform Changes

### 1. Remove GCS Resources

**File: `tf/modules/k8s-cluster/loki.tf`**

GCS resources have been removed. The file now only contains tenant authentication secrets.

**File: `tf/modules/k8s-cluster/mimir.tf`**

GCS resources have been removed. The file is now empty except for a comment.

**File: `tf/modules/k8s-cluster/main.tf`**

The `data.google_storage_project_service_account.gcs_account` data source has been removed.

**Important:** KMS keys are delete-protected and require manual intervention before Terraform can remove them. See `docs/nfs-storage-migration-manual-cleanup.md` for detailed instructions on manually removing KMS keys and keyrings.

### 2. Install NFS CSI Driver via ArgoCD

The NFS CSI driver will be installed as a Helm chart managed by ArgoCD, similar to other cluster components.

**Create ArgoCD Application Template: `charts/argocd-applications/templates/nfs-csi-driver-application.yaml`**

The template file has been created at `charts/argocd-applications/templates/nfs-csi-driver-application.yaml`. It configures the NFS CSI driver with two storage classes (`nfs-loki` and `nfs-mimir`) that use mount options to map pod UID 10001 to the NAS user account UIDs. The NFS server name is configurable via `.Values.nfs_server`.

**Note on Storage Classes:**

Yes, you need separate storage classes for Loki and Mimir because:

- Each StorageClass has static parameters (server and share/path)
- Loki uses `/tiles-loki` (or `/tiles-test-loki` for test) - the NFS export path (share name)
- Mimir uses `/tiles-mimir` (or `/tiles-test-mimir` for test) - the NFS export path (share name)
- These are different NFS export paths, so they require different StorageClasses
- Multiple PVCs can use the same StorageClass, but each StorageClass points to one specific NFS path

The `storageClasses` array in the Helm values creates both storage classes with environment-specific paths from the `loki_nfs_path` and `mimir_nfs_path` values loaded from 1Password.

### 3. Update Module Outputs

GCS-related outputs have been removed from `loki.tf` and `mimir.tf`. The bucket output references have also been removed from:

- `tf/modules/talos-cluster/main.tf` (misc_config 1Password item)
- `.github/workflows/bootstrap-cluster.yaml` (1Password secret loading)
- `charts/argocd-applications/application.yaml.tmpl` (valuesObject)

Storage classes are created by the NFS CSI driver Helm chart, so no Terraform outputs are needed.

## Helm Chart Changes

### 1. Loki Configuration

**File: `charts/loki/values.yaml`** - ✅ **Completed**

- Changed deployment mode from `SimpleScalable` to `SingleBinary` (required for filesystem storage)
- Changed storage backend from `gcs` to `filesystem`
- Updated storage class to `nfs-loki` for persistent volumes
- Removed GCS service account volume mounts and environment variables
- See the file for complete configuration

### 2. Mimir Configuration

**File: `charts/mimir/values.yaml`** - ✅ **Completed**

- Changed all storage backends from `gcs` to `filesystem` (common, alertmanager_storage, blocks_storage, ruler_storage)
- Updated storage class to `nfs-mimir` for all components with persistent volumes
- Removed GCS service account volume mounts and environment variables
- Added `global.podLabels: {}` to fix template nil pointer error
- See the file for complete configuration

### 3. Remove GCS Service Account Secret Templates

**Files removed:**

- `charts/loki/templates/gsa-loki-secret.yaml` - ✅ **Deleted**
- `charts/mimir/templates/gsa-mimir-secret.yaml` - ✅ **Deleted**

These templates created Kubernetes secrets from 1Password items for GCS service account credentials, which are no longer needed with filesystem storage.

### 4. Update Application Manifests

**Files updated:**

- `charts/loki/application.yaml` - ✅ **Completed** - Removed GCS bucket references from valuesObject
- `charts/mimir/application.yaml` - ✅ **Completed** - Removed GCS bucket references from valuesObject

The ArgoCD Application manifests have been updated to remove GCS bucket references. The values are properly templated and will be replaced during deployment.

## Migration Steps

### 1. Set up NFS on Synology

✅ **Completed** - Follow the prerequisites section above to:

- Create shared folders and NAS user accounts
- Configure NFS exports with IP restrictions
- Document the NFS paths for your environment

### 2. Update Terraform

✅ **Completed** - All Terraform changes have been made:

1. **NFS path variables added:**
   - `tf/nodes/test.auto.tfvars` - Contains `loki_nfs_path`, `mimir_nfs_path`, `loki_nfs_uid`, `mimir_nfs_uid` with actual values
   - `tf/nodes/prod.auto.tfvars` - Contains `loki_nfs_path`, `mimir_nfs_path`, `loki_nfs_uid`, `mimir_nfs_uid` with actual values

2. **GCS resources removed:**
   - `tf/modules/k8s-cluster/loki.tf` - GCS resources removed, only tenant auth secrets remain
   - `tf/modules/k8s-cluster/mimir.tf` - GCS resources removed, file is empty
   - `tf/modules/k8s-cluster/main.tf` - GCS service account data source removed

3. **Terraform variables and outputs:**
   - NFS variables added to `tf/nodes/variables.tf`
   - NFS values plumbed through `tf/nodes/cluster.tf` → `tf/modules/talos-cluster/main.tf` → 1Password `misc-config`
   - `all_node_ips` output added for NFS export configuration

**Next:** Apply Terraform changes via GitHub workflow. Terraform will update the `misc-config` 1Password item with the new NFS paths, and the bootstrap workflow will load these values for ArgoCD.

### 3. Update Helm Charts

✅ **Completed** - All Helm chart changes have been made:

1. **Loki:** `charts/loki/values.yaml` - Updated to SingleBinary mode with filesystem storage and NFS storage class
2. **Mimir:** `charts/mimir/values.yaml` - Updated to filesystem storage with NFS storage class
3. **NFS CSI driver:** `charts/argocd-applications/templates/nfs-csi-driver-application.yaml` - Created with storage classes for Loki and Mimir
4. **ArgoCD values:** `charts/argocd-applications/application.yaml.tmpl` - Updated to include NFS configuration values

### 4. Deploy via GitOps

1. **Commit and push changes:**
   - All changes are committed to the repository
   - ArgoCD will automatically sync the changes

2. **Verify deployment:**

   ```bash
   # Check NFS CSI driver is running
   kubectl get pods -n kube-system | grep nfs

   # Check storage classes created
   kubectl get storageclass nfs-loki nfs-mimir

   # Check Loki and Mimir pods are using NFS PVCs
   kubectl get pvc -n loki
   kubectl get pvc -n mimir
   ```

### Phase 5: Verification

1. **Check Pod Status:**

   ```bash
   kubectl get pods -n loki
   kubectl get pods -n mimir
   # All pods should be Running
   ```

2. **Check Logs:**

   ```bash
   # Check for any errors
   kubectl logs -n loki -l app.kubernetes.io/name=loki --tail=100
   kubectl logs -n mimir -l app.kubernetes.io/name=mimir --tail=100
   ```

3. **Test Functionality:**
   - **Loki:**
     - Send test logs
     - Query logs via Grafana
     - Verify data is being written to NFS

   - **Mimir:**
     - Check metrics are being ingested
     - Run test queries
     - Verify blocks are being created on NFS

4. **Verify NFS Storage:**

   ```bash
   # Check storage usage on Synology
   # Or from a pod:
   kubectl exec -n loki <pod-name> -- df -h /loki/storage
   kubectl exec -n mimir <pod-name> -- df -h /mimir/storage
   ```

## Testing Checklist

- [ ] NFS mounts successfully from cluster nodes
- [ ] StorageClasses created and visible
- [ ] NFS credentials secret created
- [ ] Loki pods start successfully
- [ ] Mimir pods start successfully
- [ ] PVCs created and bound
- [ ] Loki ingests and stores logs
- [ ] Loki queries work in Grafana
- [ ] Mimir ingests metrics
- [ ] Mimir queries work
- [ ] Compactors run successfully
- [ ] No GCS-related errors in logs
- [ ] Storage usage visible on Synology

## Rollback Plan

If issues occur, revert the changes in Git:

1. **Revert Git commits:**
   - Revert Helm chart changes
   - Revert Terraform changes
   - ArgoCD will automatically sync the reverted state

2. **Verify rollback:**

   ```bash
   # Check that pods are running
   kubectl get pods -n loki
   kubectl get pods -n mimir
   ```

## Cleanup Steps (After Successful Migration)

1. **Remove GCS Resources:**

   ```bash
   # Delete GCS buckets (after confirming migration success)
   # This should be done via Terraform destroy or manual deletion

   # Delete KMS keys (after bucket deletion)
   # Delete service accounts
   ```

2. **Remove 1Password Items:**
   - Delete `{cluster}-gsa-loki` item (GCS service account)
   - Delete `{cluster}-gsa-mimir` item (GCS service account)
   - Keep `{cluster}-nfs-loki-credentials` item
   - Keep `{cluster}-nfs-mimir-credentials` item

3. **Update Documentation:**
   - Update any runbooks or documentation
   - Note the migration date and any issues encountered

## Cost Impact

**Before Migration:**

- GCS Storage: ~$5/month
- GCS Egress: ~$120/month (compactor operations)
- **Total: ~$125/month**

**After Migration:**

- NFS Storage: $0 (on-prem)
- GCS Egress: $0
- **Total: $0/month**

**Savings: ~$125/month (~$1,500/year)**

## Notes and Considerations

1. **Performance:**
   - NFS performance depends on network speed between cluster and Synology
   - Consider 10G network if available
   - Monitor I/O performance after migration

2. **Backup:**
   - Ensure Synology has backup strategy
   - Consider snapshot schedules on Synology
   - Document recovery procedures

3. **Capacity Planning:**
   - Monitor NFS storage usage
   - Set up alerts for disk space
   - Plan for growth

4. **Security:**
   - Separate NAS user accounts for Loki and Mimir (principle of least privilege)
   - Each user restricted to only their respective share via Synology folder permissions
   - NFS credentials stored in 1Password (separate items for each service)
   - Use NFSv4.1 with `sys` security (standard user ID-based auth) - sufficient for trusted on-prem networks
   - Restrict NFS access to cluster node IPs (instead of `*`)
   - **UID Mapping:** NFS uses user IDs for permissions. Configure NFS mount options to map the pod's UID to the NAS user account UID. The NFS CSI driver handles this via StorageClass mountOptions.
   - Kerberos (krb5) is an option for untrusted networks but requires KDC setup, service principals, and client keytabs on all nodes

5. **High Availability:**
   - NFS is a single point of failure
   - Consider Synology HA if critical
   - Document recovery procedures

## Timeline Estimate

- **Preparation:** 2-4 hours
- **Terraform Changes:** 1-2 hours
- **Helm Chart Updates:** 1-2 hours
- **Testing:** 1-2 hours
- **Deployment:** 1 hour
- **Verification:** 1-2 hours

**Total: 7-13 hours** (can be done in a single maintenance window)

## Success Criteria

Migration is considered successful when:

1. All pods are running and healthy
2. Loki and Mimir are ingesting data
3. Queries work correctly
4. No GCS egress costs are incurred
5. Storage is visible on Synology NFS
6. No errors in logs related to storage
