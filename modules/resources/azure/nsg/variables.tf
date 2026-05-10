variable "name" {
  type        = string
  description = "NSG name"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "resource_group_name" {
  type        = string
  description = "Resource Group to create the NSG in"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the NSG"
}

# ─── Rules — list of maps, kept loose (each rule has different keys) ───
# Required keys: name, priority, destination_port_range
# Optional (with defaults): direction (Inbound), access (Allow), protocol (Tcp),
#                            source_port_range (*), destination_address_prefix (*)
# Source: pick ONE of source_address_prefix (string) or source_address_prefixes (list)
#
# Example:
#   rules = [
#     { name = "SSH",    priority = 100, destination_port_range = "22",
#       source_address_prefixes = ["1.2.3.4/32"] },
#     { name = "HTTP",   priority = 110, destination_port_range = "80",
#       source_address_prefix = "*" },
#     { name = "Calico-VXLAN", priority = 160, protocol = "Udp",
#       destination_port_range = "4789",
#       source_address_prefix = "VirtualNetwork" },
#   ]
variable "rules" {
  type        = any
  default     = []
  description = "List of security_rule definitions (see comment in variables.tf for shape)"
}
