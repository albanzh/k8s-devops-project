# Creates one Network Interface per VM, each attached to the subnet
# and a public IP. Order is preserved (index i = node_name[i]).

variable "nic_count"      { type = number }
variable "location"       { type = string }
variable "name"           { type = list(string) }
variable "resource_group" { type = string }
variable "subnet_id"      { type = string }
variable "public_ip_ids"  { type = list(string) }
variable "tags"           { type = map(string) }

resource "azurerm_network_interface" "nic" {
  count               = var.nic_count
  name                = "${var.name[count.index]}-NIC"
  location            = var.location
  resource_group_name = var.resource_group
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.public_ip_ids[count.index]
  }
}

output "nic_id" {
  value = azurerm_network_interface.nic[*].id
}

output "nic_private_ip" {
  value = azurerm_network_interface.nic[*].private_ip_address
}
