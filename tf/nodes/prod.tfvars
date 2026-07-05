# Prod-specific overrides (if any)
# Common values are in terraform.tfvars
# Common values are in terraform.tfvars
cluster_name = "tiles"
cluster_code = "p"

# Widen the kubelet within-node OOM safety margin on prod. The kubelet evicts
# low-priority pods when free memory drops below this, before the kernel
# OOM-killer fires. Prod-only: test.tfvars leaves it unset (Talos default
# 100Mi). Context: facts fables/Tiles/tiles-host-instability.md (guest-level
# wedge, tiles-wk-1, 2026-07-03).
kubelet_eviction_memory_available = "512Mi"

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
    ram_mb            = 5120
    mac_address       = "bc:24:11:d0:72:11"
    ip_address        = "10.0.128.11"
    taint             = ""
  },
  "tiles-cp-2" = {
    type              = "control"
    proxmox_node_name = "nuc-g2p-2"
    vm_id             = 7212
    cores             = 1
    ram_mb            = 3000
    mac_address       = "bc:24:11:d0:72:12"
    ip_address        = "10.0.128.12"
    taint             = ""
  },
  "tiles-cp-3" = {
    type              = "control"
    proxmox_node_name = "nuc-g3p-1"
    vm_id             = 7213
    cores             = 1
    ram_mb            = 3000
    mac_address       = "bc:24:11:d0:72:13"
    ip_address        = "10.0.128.13"
    taint             = ""
  },
  "tiles-wk-1" = {
    type              = "worker"
    proxmox_node_name = "nuc-g2p-1"
    vm_id             = 7221
    cores             = 3
    ram_mb            = 4096
    mac_address       = "bc:24:11:d0:72:21"
    ip_address        = "10.0.128.21"
    taint             = ""
  },
  "tiles-wk-2" = {
    type              = "worker"
    proxmox_node_name = "nuc-g2p-2"
    vm_id             = 7222
    cores             = 3
    ram_mb            = 6000
    mac_address       = "bc:24:11:d0:72:22"
    ip_address        = "10.0.128.22"
    taint             = ""
  },
  "tiles-wk-3" = {
    type              = "worker"
    proxmox_node_name = "nuc-g3p-1"
    vm_id             = 7223
    cores             = 3
    ram_mb            = 10000
    mac_address       = "bc:24:11:d0:72:23"
    ip_address        = "10.0.128.23"
    taint             = ""
  }
}
alloy_vm_base_id      = 400
deploy_synology_alloy = true
deploy_proxmox_alloy  = true

# Bare-metal workers (see docs/bare-metal-nodes.md)
# MAC/IP from facts fables/Tiles/Lancer.md (GMKtec EVO X2, Ryzen AI Max+ 395,
# Radeon 8060S / gfx1151, 128 GB). amdgpu firmware ships in the metal_amd
# schematic; scheduling the iGPU to pods is follow-on work. Single NVMe
# (nvme0n1, Lexar 2TB, shipped with Windows) -- the install patch pins that
# disk + wipe so Talos actually installs (first apply left it in maintenance).
metal_amd_nodes = {
  "lancer" = {
    name                   = "lancer"
    type                   = "worker"
    mac_address            = "84:47:09:75:89:a6"
    ip_address             = "10.0.128.51"
    taint                  = "heavy"
    taint_effect           = "PreferNoSchedule"
    machine_config_patches = ["patches/lancer-install-disk.yaml"]
  }
}

# MAC/IP from facts fables/kb/Computers/AceBase.md
metal_intel_nodes = {
  "acebase" = {
    name                   = "acebase"
    type                   = "worker"
    mac_address            = "00:e0:4c:5f:3d:71"
    ip_address             = "10.0.99.14"
    taint                  = "gnss"
    machine_config_patches = ["patches/acebase-gnss.yaml"]
  }
}

# It's a shame the internal volume leaks here
cluster_nfs_path = "/volume2/tiles"
