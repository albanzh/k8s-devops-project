# Creates Linux VMs using SSH-key auth only.
# Each VM can have its own size (var.node_size[count.index]).
# OS image defaults to Ubuntu 22.04 LTS Gen2 — override via image_* vars.
resource "azurerm_linux_virtual_machine" "node" {
  count                 = var.node_count
  name                  = var.node_name[count.index]
  location              = var.location
  resource_group_name   = var.resource_group
  size                  = var.node_size[count.index]
  admin_username        = var.username
  network_interface_ids = [var.network_interface_ids[count.index]]
  tags                  = var.tags

  # Optional Availability Zone (1/2/3 round-robin if zones=true; otherwise none)
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
    publisher = var.image_publisher
    offer     = var.image_offer
    sku       = var.image_sku
    version   = var.image_version
  }

  identity {
    type = "SystemAssigned"
  }
}
