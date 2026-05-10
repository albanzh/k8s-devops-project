# Creates one Network Interface per VM, each attached to the subnet
# and a public IP. Order is preserved (index i = node_name[i]).
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
