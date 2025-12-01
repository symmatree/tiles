# API Versions Strategy

This document describes the strategy for extracting and maintaining the list of API versions used for Helm templating with higher fidelity, without requiring a connection to the actual cluster during build time.

## Overview

Helm charts can be templated with greater accuracy when Helm knows which API versions and Kubernetes versions are available in the target cluster. This is achieved by:

1. **Extracting API versions from the cluster** using Helm's `Capabilities.APIVersions`
2. **Storing them in version-controlled files** for use during CI builds
3. **Regenerating them automatically** when connected to the cluster
4. **Using them during templating** to ensure charts render correctly

## Files

- `charts/extract-apis/helm-api-versions.txt` - List of API versions (one per line) in format `group/version` or `group/version/Kind`
- `charts/extract-apis/helm-kube-version.txt` - Kubernetes version in format `Major.Minor` (e.g., `1.34`)
- `charts/extract-apis/` - Helm chart used to extract Capabilities data from the cluster
- `charts/extract-apis/generate-api-versions.sh` - Script to regenerate the API versions files

## How It Works

### Extraction Method

The `extract-apis` chart uses Helm's `Capabilities` object to query the cluster for available API versions and Kubernetes version. The chart templates a ConfigMap containing:

- `APIVersions` - List of all available API versions in the cluster
- `KubeVersion` - Kubernetes version information
- `HelmVersion` - Helm version information

The extraction script (`generate-api-versions.sh`) uses `helm template --dry-run=server` to render this chart against the live cluster, then extracts the embedded YAML from the ConfigMap using `yq`.

### Generation Process

1. **Connect to cluster** - The script requires an active connection to the Kubernetes cluster (via `kubectl`)
2. **Template the extract-apis chart** - Uses `helm template --dry-run=server` to get cluster capabilities
3. **Extract YAML from ConfigMap** - Uses `yq` to extract the embedded YAML string
4. **Parse and format** - Extracts APIVersions list and KubeVersion, formats them appropriately
5. **Write to files** - Saves to `charts/extract-apis/helm-api-versions.txt` and `charts/extract-apis/helm-kube-version.txt`

### Usage in Build Process

The `build.sh` script reads these files and uses them when templating charts:

- **API Versions**: Each line from `charts/extract-apis/helm-api-versions.txt` is passed as `-a` flags to `helm template`
- **Kube Version**: The version from `charts/extract-apis/helm-kube-version.txt` is passed as `--kube-version` flag

This ensures that Helm templates are rendered with the same API version constraints as the target cluster, even when building without cluster access.

## Maintenance

### Automatic Regeneration

The `nodes-plan-apply` workflow automatically regenerates the API versions files after applying Terraform changes (when connected to the cluster via Wireguard). If changes are detected, a warning is issued but the workflow does not fail, as changes are expected during bootstrapping and cluster updates.

### Manual Regeneration

To manually regenerate the API versions files:

```bash
# Ensure you're connected to the cluster
kubectl cluster-info

# Run the generation script
./charts/extract-apis/generate-api-versions.sh
```

### When to Regenerate

The API versions should be regenerated when:

- CRDs are added or updated in the cluster
- Kubernetes version is upgraded
- New operators or controllers are installed that add new API versions
- After major cluster changes

### Committing Changes

When API versions change, commit the updated files:

```bash
git add charts/extract-apis/helm-api-versions.txt charts/extract-apis/helm-kube-version.txt
git commit -m "Update API versions from cluster"
```

## Dependencies

- **yq** - Required for extracting YAML from the ConfigMap. The workflow installs it automatically.
- **helm** - Required for templating the extract-apis chart. The workflow installs it via the helm-setup action.
- **kubectl** - Required for cluster connection. Must be configured before running the script.

## Design Decisions

### Why Use Helm Capabilities Instead of kubectl api-versions?

Helm's `Capabilities.APIVersions` provides the canonical list of API versions that Helm itself uses during templating. This ensures perfect alignment between what Helm sees and what we pass to it via `-a` flags.

### Why Store in Files Instead of Generating on Demand?

1. **Build-time access** - CI builds don't have cluster access, so we need pre-generated files
2. **Reproducibility** - Version-controlled files ensure consistent builds across different times
3. **Performance** - No need to query the cluster during every build

### Why Warn Instead of Fail on Changes?

During cluster bootstrapping and updates, API versions are expected to change. Failing the workflow would prevent necessary code submissions. Warnings alert developers to review and commit changes when appropriate.

## Related Files

- `charts/extract-apis/Chart.yaml` - Extract-apis chart definition
- `charts/extract-apis/templates/capabilities.yaml.tpl` - Template that extracts Capabilities
- `charts/extract-apis/generate-api-versions.sh` - Script to regenerate API versions files
- `charts/extract-apis/helm-api-versions.txt` - Generated API versions file
- `charts/extract-apis/helm-kube-version.txt` - Generated Kubernetes version file
- `build.sh` - Build script that uses the API versions files
- `.github/workflows/nodes-plan-apply.yaml` - Workflow that regenerates API versions
