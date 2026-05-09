# Reads an existing Resource Group by name (does NOT create one).
variable "rsname" {
  type        = string
  description = "Name of an existing Resource Group"
}

data "azurerm_resource_group" "rg" {
  name = var.rsname
}

output "rs_group_name" {
  value = data.azurerm_resource_group.rg.name
}

output "rs_group_location" {
  value = data.azurerm_resource_group.rg.location
}

output "rs_group_id" {
  value = data.azurerm_resource_group.rg.id
}
