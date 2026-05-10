variable "subnet-name" {
  type        = string
  description = "Existing subnet name"
}

variable "rs-name" {
  type        = string
  description = "Resource Group that holds the VNet"
}

variable "vnet-name" {
  type        = string
  description = "VNet name containing the subnet"
}
