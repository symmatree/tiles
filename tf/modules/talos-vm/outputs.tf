output "vm_id" {
  description = "The Proxmox VM resource ID"
  value       = proxmox_virtual_environment_vm.main.id
}

output "vm_resource" {
  description = "The Proxmox VM resource for lifecycle tracking"
  value       = proxmox_virtual_environment_vm.main
}
