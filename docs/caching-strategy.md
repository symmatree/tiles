# Caching Strategy

This document describes the caching strategy used in GitHub Actions workflows to speed up CI/CD pipelines by avoiding redundant downloads and installations.

## Overview

The caching strategy uses a combination of:

1. **Date-based invalidation** - Daily refresh to ensure caches don't become stale
2. **Content-based keys** - Lock file hashes to detect dependency changes
3. **Conditional execution** - Skip expensive operations when cache hits occur

## Helm Caching (`helm-setup` action)

### Cache Configuration

**Location**: `.github/actions/helm-setup/action.yml`

**Cached paths**:

- `**/charts/*.tgz` (downloaded Helm chart tarballs)
- `~/.config/helm/repositories.yaml` (Helm repository configuration)
- `~/.cache/helm/repository` (Helm repository index files)

**Cache key pattern**:

```yaml
${{ runner.os }}-helm-${{ inputs.helm_version }}-${{ steps.stamps.outputs.DATESTAMP }}-${{ hashFiles('**/Chart.lock', '**/Chart.yaml', 'helm-cache-poison.txt') }}
```

**Restore keys** (fallback matching):

- `${{ runner.os }}-helm-${{ inputs.helm_version }}-${{ steps.stamps.outputs.DATESTAMP }}-` (same day, any Chart.lock/Chart.yaml combination)

**Note**: Only same-day restore keys are used to ensure a clean rebuild once per day. This prevents cache entries from leaking forward across days and ensures repository indexes and chart tarballs are always from the same day.

### Guarded Operations

When `cache-hit != 'true'`, the following operations run:

1. `helm-add-repos.sh` - Adds Helm repositories from Chart.yaml dependencies
2. `helm-update-all.sh` - Runs `helm dep update --skip-refresh` for each chart

### How It Works

1. **Daily refresh**: The datestamp (`YYYYMMDD`) ensures caches are invalidated at least once per day
2. **Dependency tracking**: The `hashFiles('**/Chart.lock', '**/Chart.yaml')` detects when chart dependencies or repository URLs change
3. **Helm version isolation**: The Helm version is included in the cache key to ensure compatibility
4. **Manual invalidation**: The `helm-cache-poison.txt` file is included in the hash, allowing manual cache invalidation by modifying this file
5. **Exact match requirement**: `cache-hit` is only `true` for exact key matches (including date), ensuring daily refresh even if Chart.lock/Chart.yaml haven't changed
6. **Partial cache restores**: On cache miss, same-day restore keys allow reusing repository indexes and chart tarballs from earlier runs the same day, avoiding redundant downloads while ensuring all cached data is from the same day

## Terraform Caching (`nodes-plan-apply` workflow)

### Cache Configuration

**Location**: `.github/workflows/nodes-plan-apply.yaml`

**Cached paths**: `**/.terraform` (Terraform provider binaries and modules)

**Cache key pattern**:

```yaml
${{ runner.os }}-tf-${{ steps.stamps.outputs.DATESTAMP }}-${{ hashFiles('**/.terraform.lock.hcl', 'tf-cache-poison.txt') }}
```

**Note**: The cache key includes:
- `.terraform.lock.hcl` files - tracks provider versions (pinned after `terraform init`)
- `tf-cache-poison.txt` - allows manual cache invalidation

**Module version tracking**: The `.terraform.lock.hcl` file only tracks provider versions, not module versions. External modules (from Terraform Registry) specify versions in module blocks within `.tf` files. Unlike providers, Terraform doesn't have a lock file for modules. When external module versions change, use `tf-cache-poison.txt` to manually invalidate the cache.

**Restore keys** (fallback matching):

- `${{ runner.os }}-tf-${{ steps.stamps.outputs.DATESTAMP }}-` (same day, any lock file)

**Note**: Only same-day restore keys are used to ensure a clean rebuild once per day.

### Guarded Operations

When `cache-hit != 'true'`, the following operation runs:

- `terraform init` - Downloads providers and modules

### How It Works

1. **Daily refresh**: Datestamp ensures providers and modules are re-downloaded at least daily
2. **Provider tracking**: `.terraform.lock.hcl` hash detects provider version changes (providers are pinned in the lock file)
3. **Manual invalidation**: The `tf-cache-poison.txt` file is included in the hash, allowing manual cache invalidation by modifying this file
4. **Provider updates**: Daily refresh ensures new provider versions are available even if lock file hasn't changed

**Note on module tracking**: The `.terraform.lock.hcl` file only tracks provider versions, not module versions. External modules (from Terraform Registry) specify versions in module blocks within `.tf` files. Unlike providers, Terraform doesn't provide a lock file or easy way to report current module versions. When external module versions change, use `tf-cache-poison.txt` to manually invalidate the cache.

## Design Decisions and Notes

### Helm Caching Strategy

#### `--skip-refresh` Flag Usage

**Implementation**: `helm dep update --skip-refresh` is used in `helm-update-all.sh`.

**Rationale**: This is intentional. When `helm-add-repos.sh` runs (on cache miss), it adds repositories and performs an initial fetch for each one. The `--skip-refresh` flag prevents redundant repository index updates during the dependency update phase, since the indexes were just fetched during repository addition.

#### Daily Cache Invalidation Trade-off

**Implementation**: Cache keys include a daily datestamp, ensuring caches refresh at least once per day even if nothing has changed
in the repository.

**Rationale**: This is a deliberate trade-off between freshness and performance/cost:

- **Freshness**: The daily refresh ensures that if a chart repository updates an existing version in-place (a rare/deprecated practice), it will be picked up within 24 hours
- **Performance**: Most chart updates publish new versions rather than modifying existing ones, so the daily refresh is sufficient for the common case
- **Cost**: Reduces GitHub Actions costs by avoiding unnecessary downloads on every run
- **Speed**: Faster iteration during development when Chart.lock hasn't changed

**Expected Cache Miss Scenarios**:

- First run on a new branch (new Chart.lock or new chart dependencies)
- Chart version updates (Chart.lock changes)
- Introduction of new charts (Chart.lock changes)
- Daily cache expiration (datestamp change)

**Cost Impact**: At worst, a PR will experience 2 cache misses (one for the initial commit with changes, potentially one more if multiple commits modify charts). This is still cost-effective compared to running repository fetches and downloads on every workflow run.

#### Chart.lock and Chart.yaml Dependency

**Implementation**: Cache key depends on `hashFiles('**/Chart.lock', '**/Chart.yaml')` to detect dependency changes and repository URL changes.

**Rationale**:

- Chart.lock files represent the resolved, pinned versions of chart dependencies
- Chart.yaml files contain repository URLs and dependency specifications
- Including both ensures repository configurations stay in sync with dependency specifications
- `build.sh` enforces that Chart.lock is updated when dependencies change, so cache invalidation aligns with actual dependency changes

#### 5. Helm Version in Cache Key

**Implementation**: The Helm version (`inputs.helm_version`) is included in the cache key.

**Rationale**: Different Helm versions might handle chart formats differently. Including the version ensures cache isolation between different Helm versions, providing additional safety.

#### 6. Same-Day Only Restore Keys

**Implementation**: Restore keys only match same-day caches (no cross-day matching).

**Rationale**: This ensures a clean rebuild once per day, preventing cache entries from leaking forward across days. Repository indexes and chart tarballs are always from the same day, avoiding inconsistencies from partial cache restores across different days.

## Best Practices

1. **Always include datestamp**: Ensures caches don't become indefinitely stale
2. **Use lock files for content hashing**: Lock files represent the actual resolved dependencies
3. **Guard expensive operations**: Only run downloads/installs when cache misses occur
4. **Use restore-keys for fallback**: Allows partial cache hits when exact match isn't found
5. **Document cache-hit behavior**: The comment in `helm-setup` clarifies that cache-hit requires exact match including date

## Debugging and Troubleshooting

### Manual Cache Invalidation

Both Helm and Terraform caches include "poison" files in their cache key hashes, allowing manual cache invalidation when needed:

- **Helm cache**: Modify `helm-cache-poison.txt` (e.g., update the timestamp comment) to force Helm cache invalidation
- **Terraform cache**: Modify `tf-cache-poison.txt` (e.g., update the timestamp comment) to force Terraform cache invalidation

This is useful when:
- Cache corruption is suspected
- You need to force a fresh download of dependencies
- Debugging cache-related issues

### Debug Cache Key Glob Expansion

The `helm-setup` action includes a `debug` input that logs the expansion of glob patterns used in cache keys:

```yaml
- uses: ./.github/actions/helm-setup
  with:
    helm_version: "v4.0.0"
    debug: "true"
```

This will show which `Chart.lock`, `Chart.yaml`, and `helm-cache-poison.txt` files are being hashed for the cache key, helping diagnose cache key mismatches.

### Cache Hit/Miss Logging

GitHub Actions automatically logs cache operations. The `cache-hit` output from the cache action indicates whether an exact match was found. On cache miss, the restore-keys are checked for partial matches (same-day only).

## Related Files

- `.github/actions/helm-setup/action.yml` - Helm caching implementation
- `.github/workflows/nodes-plan-apply.yaml` - Terraform caching implementation
- `ci-tools/helm-add-repos.sh` - Adds Helm repositories
- `ci-tools/helm-update-all.sh` - Updates Helm dependencies
- `helm-cache-poison.txt` - Manual Helm cache invalidation file
- `tf-cache-poison.txt` - Manual Terraform cache invalidation file
