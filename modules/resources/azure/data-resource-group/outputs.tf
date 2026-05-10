output "rs_group_name" {
  value       = data.azurerm_resource_group.rg.name
  description = "Resource Group name"
}

output "rs_group_location" {
  value       = data.azurerm_resource_group.rg.location
  description = "Azure region the RG is in"
}

output "rs_group_id" {
  value       = data.azurerm_resource_group.rg.id
  description = "Full resource ID — useful for role assignments"
}
