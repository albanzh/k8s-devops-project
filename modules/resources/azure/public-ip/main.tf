# Creates N Standard SKU public IPs (Static allocation).
# Basic SKU is retired Sep 2025 — Standard is the only safe choice now.
# One IP per name, in the same order as the input list.

resource "azurerm_public_ip" "ip" {
  count               = length(var.names)
  name                = "${var.names[count.index]}${var.suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = var.sku
  tags                = var.tags
}
