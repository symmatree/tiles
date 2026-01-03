onepassword_vault_name = "tiles-secrets"
admin_user             = "seth.porter@gmail.com"
proxmox_storage_iso    = "local"
talos_version          = "1.12.0"
project_id             = "symm-custodes"
gcp_region             = "us-east1"

# Common Talos configuration (shared across all workspaces)
talos_variant = "nocloud"
talos_arch    = "amd64"

talos_schematic_extensions = ["qemu-guest-agent"]
talos_schematic_extra_kernel_args = [
  "vga=792",
  "-talos.halt_if_installed"
]

datasets_nfs_path = "/volume2/datasets"
