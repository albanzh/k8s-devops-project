# Generates an RSA-4096 SSH keypair and writes the private key to disk.
# The public key is exported as an output for VMs to install via admin_ssh_key.

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = var.rsa_bits
}

resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = pathexpand(var.private_key_path)
  file_permission = "0600"
}
