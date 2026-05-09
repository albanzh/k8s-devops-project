# Creates Linux VMs (Ubuntu 22.04 LTS Gen2) using SSH-key auth only.

variable "location"              { type = string }
variable "network_interface_ids" { type = list(string) }
variable "node_count"            { type = number }
variable "node_name"             { type = list(string) }
variable "node_size"             { type = string }
variable "os_disk_size"          { type = number }
variable "zones"                 { type = bool }
variable "resource_group"        { type = string }
variable "username"              { type = string }
variable "ssh_public_key"        { type = string }
variable "tags"                  { type = map(string) }

resource "azurerm_linux_virtual_machine" "node" {
  count                 = var.node_count
  name                  = var.node_name[count.index]
  location              = var.location
  resource_group_name   = var.resource_group
  size                  = var.node_size
  admin_username        = var.username
  network_interface_ids = [var.network_interface_ids[count.index]]
  tags                  = var.tags

  # Optional Availability Zone (1, 2, or 3 if av_zones is true; otherwise none)
  zone = var.zones ? tostring((count.index % 3) + 1) : null

  admin_ssh_key {
    username   = var.username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = var.os_disk_size
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }
}

output "node_id" {
  value = azurerm_linux_virtual_machine.node[*].id
}

output "node_name" {
  value = azurerm_linux_virtual_machine.node[*].name
}
