variable "names" {
  type        = list(string)
  description = "Base names. Final IP name will be '<name><suffix>' (e.g. 'k8s-master-PIP')."
}

variable "suffix" {
  type        = string
  default     = "-PIP"
  description = "Suffix appended to each base name to form the IP resource name"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "resource_group_name" {
  type        = string
  description = "Resource Group to create IPs in"
}

variable "sku" {
  type        = string
  default     = "Standard"
  description = "Public IP SKU. Use 'Standard' (Basic is retired Sep 2025)."

  validation {
    condition     = contains(["Standard", "Basic"], var.sku)
    error_message = "sku must be Standard or Basic. Strongly prefer Standard."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to every IP"
}
