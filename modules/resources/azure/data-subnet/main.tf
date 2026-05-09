# Reads an existing Subnet (inside an existing VNet) by name.
variable "subnet-name" { type = string }
variable "rs-name"     { type = string }   # Resource Group of the VNet
variable "vnet-name"   { type = string }

data "azurerm_subnet" "subnet" {
  name                 = var.subnet-name
  resource_group_name  = var.rs-name
  virtual_network_name = var.vnet-name
}

output "subnet_id" {
  value = data.azurerm_subnet.subnet.id
}
