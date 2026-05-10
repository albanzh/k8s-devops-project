output "public_key_openssh" {
  value       = tls_private_key.ssh.public_key_openssh
  description = "OpenSSH-format public key — feed into VM admin_ssh_key blocks"
}

output "private_key_path" {
  value       = local_sensitive_file.private_key.filename
  description = "Where the private key was written (already pathexpand'd)"
}
