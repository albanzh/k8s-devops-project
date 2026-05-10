# Reads an existing Resource Group by name (does NOT create one).
data "azurerm_resource_group" "rg" {
  name = var.rsname
}
