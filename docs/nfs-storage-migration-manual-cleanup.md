# Manual Cleanup Required for GCS to NFS Migration

The following GCP resources are delete-protected or require manual intervention before Terraform can remove them:

## KMS Keys (Delete-Protected)

KMS keys in Google Cloud are delete-protected by default. You must manually remove the deletion protection before Terraform can delete them.

### For Loki:
- **Keyring:** `{cluster_name}-loki`
- **Key:** `loki-storage`
- **Location:** `{gcp_region}`
- **Project:** `{kms_project_id}`

**Manual steps:**
1. Remove deletion protection from the key:
   ```bash
   gcloud kms keys update loki-storage \
     --keyring={cluster_name}-loki \
     --location={gcp_region} \
     --project={kms_project_id} \
     --no-deletion-protection
   ```
2. Remove the key:
   ```bash
   gcloud kms keys delete loki-storage \
     --keyring={cluster_name}-loki \
     --location={gcp_region} \
     --project={kms_project_id}
   ```
3. Remove the keyring (after all keys are deleted):
   ```bash
   gcloud kms keyrings delete {cluster_name}-loki \
     --location={gcp_region} \
     --project={kms_project_id}
   ```

### For Mimir:
- **Keyring:** `{cluster_name}-mimir`
- **Key:** `mimir-storage`
- **Location:** `{gcp_region}`
- **Project:** `{kms_project_id}`

**Manual steps:**
1. Remove deletion protection from the key:
   ```bash
   gcloud kms keys update mimir-storage \
     --keyring={cluster_name}-mimir \
     --location={gcp_region} \
     --project={kms_project_id} \
     --no-deletion-protection
   ```
2. Remove the key:
   ```bash
   gcloud kms keys delete mimir-storage \
     --keyring={cluster_name}-mimir \
     --location={gcp_region} \
     --project={kms_project_id}
   ```
3. Remove the keyring (after all keys are deleted):
   ```bash
   gcloud kms keyrings delete {cluster_name}-mimir \
     --location={gcp_region} \
     --project={kms_project_id}
   ```

## Alternative: Remove from Terraform State First

If you want Terraform to proceed without waiting for manual deletion, you can remove these resources from Terraform state first:

```bash
# For Loki
terraform state rm 'module.cluster.module.k8s.module.loki_encryption_key'
terraform state rm 'module.cluster.module.k8s.module.loki_buckets'

# For Mimir
terraform state rm 'module.cluster.module.k8s.module.mimir_encryption_key'
terraform state rm 'module.cluster.module.k8s.module.mimir_buckets'
```

Then manually delete the KMS keys and keyrings as described above. The GCS buckets can be deleted via the GCP console or gcloud CLI.

## GCS Buckets

The following GCS buckets will be deleted by Terraform, but you may want to verify they're empty first:

### Loki buckets:
- `{cluster_name}-loki-chunks`
- `{cluster_name}-loki-ruler` (versioning enabled)
- `{cluster_name}-loki-admin` (versioning enabled)

### Mimir buckets:
- `{cluster_name}-mimir-blocks`
- `{cluster_name}-mimir-alertmanager` (versioning enabled)
- `{cluster_name}-mimir-ruler` (versioning enabled)

**Note:** Buckets with versioning enabled may have object versions that need to be deleted before the bucket can be removed. Use `gsutil -m rm -r gs://bucket-name/**` to remove all versions.

## Service Accounts

The following service accounts will be deleted by Terraform:
- `{cluster_name}-loki@{main_project_id}.iam.gserviceaccount.com`
- `{cluster_name}-mimir@{main_project_id}.iam.gserviceaccount.com`

These should delete cleanly, but if they have IAM bindings elsewhere, those may need to be removed first.

## 1Password Items

The following 1Password items will be deleted by Terraform:
- `{cluster_name}-gsa-loki`
- `{cluster_name}-gsa-mimir`

These should delete cleanly.

**Note:** The following fields in `{cluster_name}-misc-config` are no longer used and can be manually removed from 1Password after migration:
- `loki_bucket_chunks`
- `loki_bucket_ruler`
- `loki_bucket_admin`
- `mimir_bucket_blocks`
- `mimir_bucket_ruler`
- `mimir_bucket_alertmanager`
