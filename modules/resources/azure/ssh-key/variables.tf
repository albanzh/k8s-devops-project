variable "private_key_path" {
  type        = string
  default     = "~/ssh_key.pem"
  description = "Where to write the private key. ~ is expanded. File is chmod 600."
}

variable "rsa_bits" {
  type        = number
  default     = 4096
  description = "RSA key size. 4096 is the safe default; 2048 is also acceptable."
}
