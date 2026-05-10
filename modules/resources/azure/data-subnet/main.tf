# Reads an existing Subnet (inside an existing VNet) by name.
data "azurerm_subnet" "subnet" {
  name                 = var.subnet-name
  resource_group_name  = var.rs-name
  virtual_network_name = var.vnet-name
}
