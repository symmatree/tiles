onepassword_vault_name = "tiles-secrets"
admin_user             = "seth.porter@gmail.com"
proxmox_storage_iso    = "local"
talos_version          = "1.12.0"
project_id             = "symm-custodes"
seed_project_id        = "symm-custodes"
gcp_region             = "us-east1"
dns_zone_ad_local      = "ad-local-symmatree-com"
dns_zone_local         = "local-symmatree-com"

# Common Talos configuration (shared across all workspaces)
talos_arch              = "amd64"
talos_vm_variant        = "nocloud"
talos_metal_amd_variant = "metal"

# Network and storage
unifi_controller_url = "https://morpheus.local.symmatree.com:443"
nfs_server           = "raconteur.ad.local.symmatree.com"
synology_host        = "https://raconteur.ad.local.symmatree.com:5001"

datasets_nfs_path = "/volume2/datasets"

unifi_network_name = "10.0.0.1_default"
