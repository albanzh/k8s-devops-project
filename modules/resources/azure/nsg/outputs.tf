output "id" {
  value       = azurerm_network_security_group.nsg.id
  description = "NSG resource ID — feed into NIC associations"
}

output "name" {
  value       = azurerm_network_security_group.nsg.name
  description = "NSG name"
}
