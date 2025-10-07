# Upload Talos ISO to Proxmox
resource "proxmox_virtual_environment_download_file" "talos_iso" {
  for_each     = toset(data.proxmox_virtual_environment_nodes.nodes.names)
  content_type = "iso"
  datastore_id = var.proxmox_storage_iso
  node_name    = each.value

  url       = "https://factory.talos.dev/image/${var.talos_schematic}/v${var.talos_version}/${var.talos_variant}-${var.talos_arch}.iso"
  file_name = "talos-${var.talos_version}-${var.talos_variant}-${var.talos_arch}.iso"

  # Only download if file doesn't exist
  overwrite = false
}

# # Control plane VMs
# resource "proxmox_virtual_environment_vm" "talos_control" {
#   count = var.control_plane_count

#   name        = "${var.cluster_name}-control-${count.index + 1}"
#   description = "Talos Linux Control Plane Node ${count.index + 1}"
#   node_name   = var.proxmox_node_name
#   vm_id       = var.control_plane_vm_id_start + count.index

#   agent {
#     enabled = true
#   }

#   cpu {
#     cores = var.control_plane_cpu_cores
#     type  = "host"
#   }

#   memory {
#     dedicated = var.control_plane_memory_mb
#   }

#   network_device {
#     bridge      = var.proxmox_network_bridge
#     mac_address = var.control_plane_mac_addresses[count.index]
#   }

#   disk {
#     datastore_id = var.proxmox_storage_vm
#     file_id      = proxmox_virtual_environment_download_file.talos_iso.id
#     interface    = "ide0"
#     size         = 4
#   }

#   disk {
#     datastore_id = var.proxmox_storage_vm
#     file_format  = "raw"
#     interface    = "scsi0"
#     iothread     = true
#     ssd          = true
#     size         = var.control_plane_disk_size_gb
#   }

#   boot_order = ["ide0", "scsi0"]

#   operating_system {
#     type = "l26"
#   }

#   serial_device {
#     device = "socket"
#   }

#   vga {
#     enabled = true
#     type    = "serial0"
#   }

#   initialization {
#     dns {
#       servers = var.dns_servers
#     }

#     ip_config {
#       ipv4 {
#         address = "${var.control_plane_ips[count.index]}/${var.network_cidr_bits}"
#         gateway = var.network_gateway
#       }
#     }
#   }

#   lifecycle {
#     ignore_changes = [
#       boot_order,
#       disk[0].file_id,
#     ]
#   }
# }

# # Worker VMs
# resource "proxmox_virtual_environment_vm" "talos_worker" {
#   count = var.worker_count

#   name        = "${var.cluster_name}-worker-${count.index + 1}"
#   description = "Talos Linux Worker Node ${count.index + 1}"
#   node_name   = var.proxmox_node_name
#   vm_id       = var.worker_vm_id_start + count.index

#   agent {
#     enabled = true
#   }

#   cpu {
#     cores = var.worker_cpu_cores
#     type  = "host"
#   }

#   memory {
#     dedicated = var.worker_memory_mb
#   }

#   network_device {
#     bridge      = var.proxmox_network_bridge
#     mac_address = var.worker_mac_addresses[count.index]
#   }

#   disk {
#     datastore_id = proxmox_virtual_environment_download_file.talos_iso.datastore_id
#     file_id      = proxmox_virtual_environment_download_file.talos_iso.id
#     interface    = "ide0"
#     size         = 4
#   }

#   disk {
#     datastore_id = var.proxmox_storage_vm
#     file_format  = "raw"
#     interface    = "scsi0"
#     iothread     = true
#     ssd          = true
#     size         = var.worker_disk_size_gb
#   }

#   boot_order = ["ide0", "scsi0"]

#   operating_system {
#     type = "l26"
#   }

#   serial_device {
#     device = "socket"
#   }

#   vga {
#     enabled = true
#     type    = "serial0"
#   }

#   initialization {
#     dns {
#       servers = var.dns_servers
#     }

#     ip_config {
#       ipv4 {
#         address = "${var.worker_ips[count.index]}/${var.network_cidr_bits}"
#         gateway = var.network_gateway
#       }
#     }
#   }

#   lifecycle {
#     ignore_changes = [
#       boot_order,
#       disk[0].file_id,
#     ]
#   }
# }
