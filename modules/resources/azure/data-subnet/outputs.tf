output "subnet_id" {
  value       = data.azurerm_subnet.subnet.id
  description = "Full subnet ID — used by NICs"
}

output "address_prefixes" {
  value       = data.azurerm_subnet.subnet.address_prefixes
  description = "CIDR blocks assigned to this subnet"
}
