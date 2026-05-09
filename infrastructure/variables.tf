# ─────────────────────────────────────────────────────────────────
# variables.tf — Inputs needed by main.tf
#
# Names (RG/VNet/Subnet/VM size) live in locals.tf inside main.tf.
# These are env-level secrets/preferences.
# ─────────────────────────────────────────────────────────────────

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "username" {
  description = "Linux admin username on every VM"
  type        = string
  default     = "azureuser"
}

variable "letsencrypt_email" {
  description = "Email used by Let's Encrypt for cert expiry notifications"
  type        = string
}

variable "admin_source_cidr" {
  description = "CIDRs allowed for SSH + K8s API (your public IP/range)"
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for c in var.admin_source_cidr : can(cidrhost(c, 0))])
    error_message = "admin_source_cidr must be a list of valid CIDR blocks."
  }
}

variable "use_staging_issuer" {
  description = "If true, use Let's Encrypt STAGING (avoids prod rate limits while testing)"
  type        = bool
  default     = true
}
