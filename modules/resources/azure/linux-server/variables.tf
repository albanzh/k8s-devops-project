variable "location" {
  type        = string
  description = "Azure region"
}

variable "network_interface_ids" {
  type        = list(string)
  description = "NIC IDs (one per VM, same order as node_name)"
}

variable "node_count" {
  type        = number
  description = "Number of VMs to create (must match length(node_name), length(node_size), length(network_interface_ids))"
}

variable "node_name" {
  type        = list(string)
  description = "VM names (used as the VM resource name)"
}

# ─── VM size — list, one entry per VM ─────────────────────────────────
# Lets you mix sizes: e.g. master=Standard_D4s_v3, workers=Standard_B2s.
variable "node_size" {
  type        = list(string)
  description = "Azure VM SKU per node (length must equal node_count)"
}

variable "os_disk_size" {
  type        = number
  default     = 30
  description = "OS disk size in GB"
}

variable "zones" {
  type        = bool
  default     = false
  description = "If true, distribute VMs across availability zones 1/2/3 round-robin"
}

variable "resource_group" {
  type        = string
  description = "Resource Group to create VMs in"
}

variable "username" {
  type        = string
  description = "Linux admin username"
}

variable "ssh_public_key" {
  type        = string
  description = "OpenSSH-format public key (e.g. tls_private_key.ssh.public_key_openssh)"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to every VM"
}

# ─── OS image — fully configurable, Ubuntu 22.04 LTS by default ───────
# Find more images:
#   az vm image list-publishers --location westeurope -o table
#   az vm image list --offer 0001-com-ubuntu-server-jammy --all -o table
variable "image_publisher" {
  type        = string
  default     = "Canonical"
  description = "Azure VM image publisher (e.g. Canonical, RedHat, Debian, OpenLogic)"
}

variable "image_offer" {
  type        = string
  default     = "0001-com-ubuntu-server-jammy"
  description = "Azure VM image offer (e.g. 0001-com-ubuntu-server-jammy for Ubuntu 22.04, 0001-com-ubuntu-server-noble for 24.04)"
}

variable "image_sku" {
  type        = string
  default     = "22_04-lts-gen2"
  description = "Azure VM image SKU (e.g. 22_04-lts-gen2, 24_04-lts-gen2)"
}

variable "image_version" {
  type        = string
  default     = "latest"
  description = "Azure VM image version (use 'latest' or pin to e.g. '22.04.202401080')"
}
