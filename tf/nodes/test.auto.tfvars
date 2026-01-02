# Test-specific overrides (if any)
# Common values are in terraform.tfvars
cluster_name = "tiles-test"
cluster_code = "x"

control_plane_vip = "10.0.192.10"
external_ip_cidr  = "10.0.193.0/24"
service_cidr      = "10.0.200.0/21"
pod_cidr          = "10.0.208.0/20"

virtual_machines = {
  "tiles-test-cp" = {
    type              = "control"
    proxmox_node_name = "nuc-g3p-2"
    vm_id             = 7411
    cores             = 2
    ram_mb            = 5120
    mac_address       = "bc:24:11:d0:74:11"
    ip_address        = "10.0.192.11"
  },
  "tiles-test-wk" = {
    type              = "worker"
    proxmox_node_name = "nuc-g3p-2"
    vm_id             = 7421
    cores             = 2
    ram_mb            = 8192
    mac_address       = "bc:24:11:d0:74:21"
    ip_address        = "10.0.192.21"
  }
}

# It's a shame the internal volume leaks here
loki_nfs_path  = "/volume2/tiles-test-loki"
mimir_nfs_path = "/volume2/tiles-test-mimir"
