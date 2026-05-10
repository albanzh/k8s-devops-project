variable "name" {
  type        = string
  description = "Load Balancer name. Public IP becomes '<name>-pip'."
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "resource_group_name" {
  type        = string
  description = "Resource Group to create LB resources in"
}

variable "backend_nic_ids" {
  type        = list(string)
  description = "NIC IDs to associate with the backend pool (one per VM)"
}

variable "nic_ip_config_name" {
  type        = string
  default     = "internal"
  description = "ip_configuration name on the NICs (must match what network-interface module uses)"
}

variable "ports" {
  type        = list(number)
  default     = [80, 443]
  description = "Ports to load-balance. One probe + one rule is created per port."
}

variable "probe_interval_seconds" {
  type        = number
  default     = 5
  description = "Seconds between health-check pings (5–60)"
}

variable "probe_unhealthy_threshold" {
  type        = number
  default     = 2
  description = "Number of consecutive failed probes before marking backend unhealthy"
}

variable "enable_outbound_rule" {
  type        = bool
  default     = false
  description = "Set to true ONLY if your VMs have NO public IPs of their own. With per-VM public IPs, outbound goes via those — leave this false to avoid double-NAT."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to LB and frontend IP"
}
