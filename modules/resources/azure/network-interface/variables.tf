variable "nic_count" {
  type        = number
  description = "Number of NICs to create (must match length(name) and length(public_ip_ids))"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "name" {
  type        = list(string)
  description = "List of base names — final NIC name is '<name>-NIC'"
}

variable "resource_group" {
  type        = string
  description = "Resource Group to create NICs in"
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID the NICs attach to"
}

variable "public_ip_ids" {
  type        = list(string)
  description = "Public IP IDs (1 per NIC, same order as name)"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to every NIC"
}
