output "public_ip_address" {
  value       = azurerm_public_ip.lb.ip_address
  description = "Public IP of the LB frontend — point DNS here"
}

output "public_ip_id" {
  value       = azurerm_public_ip.lb.id
  description = "Frontend public IP resource ID"
}

output "lb_id" {
  value       = azurerm_lb.main.id
  description = "Load Balancer resource ID"
}

output "backend_pool_id" {
  value       = azurerm_lb_backend_address_pool.main.id
  description = "Backend pool ID — useful if you need to add more NICs later"
}
