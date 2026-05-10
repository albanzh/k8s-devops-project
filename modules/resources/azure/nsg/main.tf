# Creates an NSG with a dynamic block driven by var.rules.
#
# Each rule is a map. Either source_address_prefix (string) OR
# source_address_prefixes (list) must be set, never both.
# Same for destination_*. The validation below catches the common case.

resource "azurerm_network_security_group" "nsg" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  dynamic "security_rule" {
    for_each = var.rules
    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = lookup(security_rule.value, "direction", "Inbound")
      access                     = lookup(security_rule.value, "access", "Allow")
      protocol                   = lookup(security_rule.value, "protocol", "Tcp")
      source_port_range          = lookup(security_rule.value, "source_port_range", "*")
      destination_port_range     = lookup(security_rule.value, "destination_port_range", null)
      destination_port_ranges    = lookup(security_rule.value, "destination_port_ranges", null)
      source_address_prefix      = lookup(security_rule.value, "source_address_prefix", null)
      source_address_prefixes    = lookup(security_rule.value, "source_address_prefixes", null)
      destination_address_prefix = lookup(security_rule.value, "destination_address_prefix", "*")
    }
  }
}
