# Control plane outputs
# output "control_plane_vm_ids" {
#   description = "VM IDs of control plane nodes"
#   value       = proxmox_virtual_environment_vm.talos_control[*].vm_id
# }

# output "control_plane_names" {
#   description = "Names of control plane VMs"
#   value       = proxmox_virtual_environment_vm.talos_control[*].name
# }

# output "control_plane_ips" {
#   description = "IP addresses of control plane nodes"
#   value       = var.control_plane_ips
# }

# output "control_plane_mac_addresses" {
#   description = "MAC addresses of control plane nodes"
#   value       = proxmox_virtual_environment_vm.talos_control[*].network_device[0].mac_address
# }

# # Worker outputs
# output "worker_vm_ids" {
#   description = "VM IDs of worker nodes"
#   value       = proxmox_virtual_environment_vm.talos_worker[*].vm_id
# }

# output "worker_names" {
#   description = "Names of worker VMs"
#   value       = proxmox_virtual_environment_vm.talos_worker[*].name
# }

# output "worker_ips" {
#   description = "IP addresses of worker nodes"
#   value       = var.worker_ips
# }

# output "worker_mac_addresses" {
#   description = "MAC addresses of worker nodes"
#   value       = proxmox_virtual_environment_vm.talos_worker[*].network_device[0].mac_address
# }

# # Cluster outputs
# output "cluster_endpoints" {
#   description = "Talos cluster endpoints for talosctl configuration"
#   value       = var.control_plane_ips
# }

output "talos_iso_id" {
  description = "ID of the uploaded Talos ISO"
  value       = proxmox_virtual_environment_download_file.talos_iso.id
}

# Summary output for easy reference
# output "cluster_summary" {
#   description = "Summary of the created Talos cluster"
#   value = {
#     cluster_name     = var.cluster_name
#     talos_version    = var.talos_version
#     control_planes   = length(proxmox_virtual_environment_vm.talos_control)
#     workers         = length(proxmox_virtual_environment_vm.talos_worker)
#     control_plane_ips = var.control_plane_ips
#     worker_ips      = var.worker_ips
#   }
# }
