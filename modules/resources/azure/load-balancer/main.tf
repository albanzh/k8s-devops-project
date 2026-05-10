# Azure Standard Load Balancer in front of N backend NICs.
#
# Frontend: one public IP (Standard SKU, Static).
# Backend pool: the NIC IDs you pass in.
# For each port in var.ports: a TCP health probe + an LB rule.
#
# TCP probe on port 80 means "the port answers" — fine for NGINX which
# is always listening regardless of any matching ingress rule.

# Frontend public IP
resource "azurerm_public_ip" "lb" {
  name                = "${var.name}-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# The Load Balancer itself (Standard SKU; Basic is retired Sep 2025)
resource "azurerm_lb" "main" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  tags                = var.tags

  frontend_ip_configuration {
    name                 = "frontend"
    public_ip_address_id = azurerm_public_ip.lb.id
  }
}

# Backend address pool — VMs land here via NIC association below
resource "azurerm_lb_backend_address_pool" "main" {
  loadbalancer_id = azurerm_lb.main.id
  name            = "${var.name}-backend"
}

# Attach each backend NIC to the pool
resource "azurerm_network_interface_backend_address_pool_association" "main" {
  count                   = length(var.backend_nic_ids)
  network_interface_id    = var.backend_nic_ids[count.index]
  ip_configuration_name   = var.nic_ip_config_name
  backend_address_pool_id = azurerm_lb_backend_address_pool.main.id
}

# Health probes — one per port. TCP probe is enough for NGINX.
resource "azurerm_lb_probe" "port" {
  for_each            = toset([for p in var.ports : tostring(p)])
  loadbalancer_id     = azurerm_lb.main.id
  name                = "probe-${each.value}"
  protocol            = "Tcp"
  port                = tonumber(each.value)
  interval_in_seconds = var.probe_interval_seconds
  number_of_probes    = var.probe_unhealthy_threshold
}

# LB rules — one per port. Maps frontend:port → backend pool:port.
resource "azurerm_lb_rule" "port" {
  for_each                       = toset([for p in var.ports : tostring(p)])
  loadbalancer_id                = azurerm_lb.main.id
  name                           = "rule-${each.value}"
  protocol                       = "Tcp"
  frontend_port                  = tonumber(each.value)
  backend_port                   = tonumber(each.value)
  frontend_ip_configuration_name = "frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.main.id]
  probe_id                       = azurerm_lb_probe.port[each.value].id
  enable_tcp_reset               = true
  idle_timeout_in_minutes        = 4
}

# Outbound rule — Standard LB blocks default outbound when a backend pool
# exists. Without explicit outbound config, VMs in the pool would lose
# internet access. We give them outbound via the LB's frontend IP.
resource "azurerm_lb_outbound_rule" "main" {
  count                   = var.enable_outbound_rule ? 1 : 0
  name                    = "${var.name}-outbound"
  loadbalancer_id         = azurerm_lb.main.id
  protocol                = "All"
  backend_address_pool_id = azurerm_lb_backend_address_pool.main.id

  frontend_ip_configuration {
    name = "frontend"
  }
}
