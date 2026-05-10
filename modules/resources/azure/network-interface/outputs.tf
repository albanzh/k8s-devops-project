output "nic_id" {
  value       = azurerm_network_interface.nic[*].id
  description = "List of NIC IDs (same order as input name list)"
}

output "nic_private_ip" {
  value       = azurerm_network_interface.nic[*].private_ip_address
  description = "List of private IPs assigned to each NIC"
}
