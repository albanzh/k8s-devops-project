output "node_id" {
  value       = azurerm_linux_virtual_machine.node[*].id
  description = "List of VM resource IDs (same order as node_name)"
}

output "node_name" {
  value       = azurerm_linux_virtual_machine.node[*].name
  description = "List of VM names (echoed back from input)"
}

output "node_identity_principal_ids" {
  value       = azurerm_linux_virtual_machine.node[*].identity[0].principal_id
  description = "SystemAssigned managed identity principal IDs — useful for role assignments"
}
