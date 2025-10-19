# Example terraform.tfvars file
# Copy this to terraform.tfvars and customize for your environment

# Proxmox connection details
proxmox_endpoint             = "https://nuc-g3p-1.local.symmatree.com:8006/"
proxmox_username             = "root@pam"
proxmox_ssh_private_key_path = "~/.ssh/id_rsa"
proxmox_storage_iso          = "local"
proxmox_storage_vm           = "local-lvm"
proxmox_network_bridge       = "vmbr0"

# Cluster configuration
cluster_name  = "talos"
talos_version = "1.11.2"
talos_variant = "nocloud"
talos_arch    = "amd64"

# Network configuration
network_gateway   = "10.0.1.1"
network_cidr_bits = 24
# dns_servers       = ["10.0.1.1", "1.1.1.1"]

# Control plane configuration
control_plane_count        = 1
control_plane_cpu_cores    = 2
control_plane_memory_mb    = 4096
control_plane_disk_size_gb = 50
control_plane_vm_id_start  = 100
control_plane_ips          = ["10.0.1.50"]
# Optional: specify MAC addresses to ensure consistent IPs
# control_plane_mac_addresses = ["02:00:00:00:01:50"]

# Worker configuration
worker_count        = 1
worker_cpu_cores    = 4
worker_memory_mb    = 8192
worker_disk_size_gb = 100
worker_vm_id_start  = 200
worker_ips          = ["10.0.1.51"]
# Optional: specify MAC addresses to ensure consistent IPs
# worker_mac_addresses = ["02:00:00:00:01:51"]

# For multi-node setup, example:
# control_plane_count = 3
# control_plane_ips   = ["10.0.1.50", "10.0.1.51", "10.0.1.52"]
# worker_count = 3
# worker_ips   = ["10.0.1.60", "10.0.1.61", "10.0.1.62"]
