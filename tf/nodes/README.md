# Terraform Talos on Proxmox

This Terraform configuration creates Talos Linux VMs on Proxmox for a Kubernetes homelab cluster.

## Features

- Automatically downloads the latest Talos ISO with qemu-guest-agent extension
- Creates configurable control plane and worker nodes
- Sets up static IP addresses and MAC addresses
- Configures VMs with appropriate resources for Kubernetes workloads
- Uses the same Talos image schematic as the existing cluster (`ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515`)

## Prerequisites

1. **Proxmox VE** with API access
2. **Terraform** >= 1.0
3. **SSH access** to the Proxmox host
4. **Network planning** - Static IP addresses for your cluster nodes

## Quick Start

1. **Copy the example variables file:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit `terraform.tfvars`** with your Proxmox and network details:
   - Proxmox endpoint, credentials, and storage
   - Network configuration (IPs, gateway, DNS)
   - VM resource specifications

3. **Initialize and apply:**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. **After VMs are created:**
   - VMs will boot from the Talos ISO initially
   - Follow the existing Talos installation process in `../tales/talos/README.md`
   - Use `talosctl apply-config` to configure each node
   - Bootstrap the cluster with `talosctl bootstrap`

## Configuration

### Key Variables

- `control_plane_count`: Number of control plane nodes (default: 1, recommend 3 for HA)
- `worker_count`: Number of worker nodes (default: 1)
- `control_plane_ips` / `worker_ips`: Static IP addresses for nodes
- CPU, memory, and disk sizes for each node type

### Network Requirements

- Static IP addresses that don't conflict with DHCP
- Proper DNS resolution for node hostnames
- Network access to the Proxmox API

### Storage Configuration

- `proxmox_storage_iso`: Storage for ISO files (usually "local")
- `proxmox_storage_vm`: Storage for VM disks (e.g., "local-lvm")

## Outputs

After applying, Terraform will output:
- VM IDs and names
- IP addresses and MAC addresses
- Cluster summary information

## Integration with Existing Setup

This Terraform configuration is designed to work with the existing Talos setup in `../tales/talos/`:
- Uses the same Talos version and image schematic
- Creates VMs with the expected network configuration
- Follows the same naming conventions

After creating VMs with Terraform, use the existing Talos installation scripts and procedures.

## Cleanup

To destroy the infrastructure:
```bash
terraform destroy
```

Note: This will delete all VMs and associated resources. Ensure you have backups if needed.
