output "ids" {
  value       = azurerm_public_ip.ip[*].id
  description = "List of public IP resource IDs (same order as names input)"
}

output "ip_addresses" {
  value       = azurerm_public_ip.ip[*].ip_address
  description = "List of allocated IP addresses"
}
