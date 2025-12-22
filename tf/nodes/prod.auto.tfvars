# Prod-specific overrides (if any)
# Common values are in terraform.tfvars
# Common values are in terraform.tfvars
cluster_name = "tiles"
cluster_code = "p"

# Network configuration for tiles cluster (10.0.128.0/18 block)
control_plane_vip = "10.0.128.10"
external_ip_cidr  = "10.0.129.0/24"
service_cidr      = "10.0.136.0/21"
pod_cidr          = "10.0.144.0/20"

virtual_machines = {
  "tiles-cp-1" = {
    type              = "control"
    proxmox_node_name = "nuc-g2p-1"
    vm_id             = 7211
    cores             = 1
    ram_mb            = 2000
    mac_address       = "bc:24:11:d0:72:11"
    ip_address        = "10.0.128.11"
  },
  "tiles-cp-2" = {
    type              = "control"
    proxmox_node_name = "nuc-g2p-2"
    vm_id             = 7212
    cores             = 1
    ram_mb            = 2000
    mac_address       = "bc:24:11:d0:72:12"
    ip_address        = "10.0.128.12"
  },
  "tiles-cp-3" = {
    type              = "control"
    proxmox_node_name = "nuc-g3p-1"
    vm_id             = 7213
    cores             = 1
    ram_mb            = 2000
    mac_address       = "bc:24:11:d0:72:13"
    ip_address        = "10.0.128.13"
  },
  "tiles-wk-1" = {
    type              = "worker"
    proxmox_node_name = "nuc-g2p-1"
    vm_id             = 7221
    cores             = 3
    ram_mb            = 7000
    mac_address       = "bc:24:11:d0:72:21"
    ip_address        = "10.0.128.21"
  },
  "tiles-wk-2" = {
    type              = "worker"
    proxmox_node_name = "nuc-g2p-2"
    vm_id             = 7222
    cores             = 3
    ram_mb            = 7000
    mac_address       = "bc:24:11:d0:72:22"
    ip_address        = "10.0.128.22"
  },
  "tiles-wk-3" = {
    type              = "worker"
    proxmox_node_name = "nuc-g3p-1"
    vm_id             = 7223
    cores             = 3
    ram_mb            = 11000
    mac_address       = "bc:24:11:d0:72:23"
    ip_address        = "10.0.128.23"
  }
}
