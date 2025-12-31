# Talos Configuration Application Script

## Overview

`apply-talos-config.sh` applies Talos configuration after Terraform creates VMs. It replaces the Terraform Talos provider to support multi-document configs (like Layer2VIPConfig).

## Idempotency

The script is **safe to run multiple times**:

- **Secrets**: Reuses existing secrets from 1Password (never regenerates for existing clusters)
- **apply-config**: Idempotent - only applies if config changed
- **bootstrap**: Idempotent - only bootstraps if not already bootstrapped
- **kubeconfig**: Safe to regenerate

**Critical**: Never regenerates secrets for an existing cluster - this would break everything.

## When to Run

The script runs **automatically after terraform apply** in the GitHub Actions workflow. Since it's idempotent, it's safe to run every time - it will:
- Reuse existing secrets
- Only apply configs if changed
- Only bootstrap if needed
- Regenerate kubeconfig (safe)

## Required Environment Variables

Loaded from 1Password `{cluster_name}-misc-config`:
- `cluster_name`
- `pod_cidr`
- `service_cidr`
- `control_plane_vip`
- `control_plane_vip_link`
- `talos_install_image`
- `control_plane_ips` (comma-separated)
- `bootstrap_ip`
- `worker_ips` (comma-separated, optional)
- `vault_name`

## What It Does

1. Loads or generates machine secrets (reuses if exist)
2. Generates machine configs with envsubst templates
3. Applies configs to control plane nodes
4. Applies configs to worker nodes (if any)
5. Bootstraps cluster (idempotent)
6. Gets kubeconfig
7. Stores secrets/configs in 1Password
