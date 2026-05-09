locals {
  rsname       = "rg_es_kube_test"
  vnet_name    = "vnet_es_kube_test"
  vnet_rg      = "rg_es_kube_test"
  vm_subnet    = "snet_es_kube_test"
  os_disk_size = 127
  av_zones     = false
  vm_size      = "Standard_D4s_v3"

  master_name  = "k8s-master"
  worker_names = ["k8s-worker-1", "k8s-worker-2"]
  node_name    = concat([local.master_name], local.worker_names)

  common_tags = {
    environment = "demo"
    project     = "k8s-bookstore"
    managed_by  = "terraform"
  }
}

# ---------------------------------------------------------------
# SSH Key for Ansible access
# ---------------------------------------------------------------
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "ssh_private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = pathexpand("~/ssh_key.pem")
  file_permission = "0600"
}

# ---------------------------------------------------------------
# Data sources
# ---------------------------------------------------------------
module "resource_group" {
  source = "../modules/resources/azure/data-resource-group"
  rsname = local.rsname
}

module "linux_subnet" {
  source      = "../modules/resources/azure/data-subnet"
  subnet-name = local.vm_subnet
  rs-name     = local.vnet_rg
  vnet-name   = local.vnet_name
}

# ---------------------------------------------------------------
# Public IPs (Standard SKU; Basic is retired Sept 2025)
# ---------------------------------------------------------------
resource "azurerm_public_ip" "k8s" {
  count               = length(local.node_name)
  name                = "${local.node_name[count.index]}-PIP"
  location            = module.resource_group.rs_group_location
  resource_group_name = module.resource_group.rs_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

# ---------------------------------------------------------------
# Network Security Group
#
# SSH + K8s API are restricted to admin_source_cidr (your public IP).
# HTTP/HTTPS stay open to the world so public ingress works.
# Intra-cluster ports (kubelet, etcd, Calico) are scoped to VirtualNetwork.
# ---------------------------------------------------------------
resource "azurerm_network_security_group" "k8s" {
  name                = "k8s-nsg"
  location            = module.resource_group.rs_group_location
  resource_group_name = module.resource_group.rs_group_name

  security_rule {
    name                       = "SSH-admin"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = var.admin_source_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP-public"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTPS-public"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "K8s-API-admin"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6443"
    source_address_prefixes    = var.admin_source_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Kubelet-API"
    priority                   = 150
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "10250"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Calico-VXLAN"
    priority                   = 160
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "4789"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Calico-BGP"
    priority                   = 170
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "179"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "ETCD"
    priority                   = 180
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "2379-2380"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  tags = local.common_tags
}

# ---------------------------------------------------------------
# NICs (with public IPs)
# ---------------------------------------------------------------
module "nic" {
  source         = "../modules/resources/azure/network-interface"
  nic_count      = length(local.node_name)
  location       = module.resource_group.rs_group_location
  name           = local.node_name
  resource_group = module.resource_group.rs_group_name
  subnet_id      = module.linux_subnet.subnet_id
  public_ip_ids  = azurerm_public_ip.k8s[*].id
  tags           = local.common_tags
}

# Associate NSG to each NIC
resource "azurerm_network_interface_security_group_association" "k8s" {
  count                     = length(local.node_name)
  network_interface_id      = module.nic.nic_id[count.index]
  network_security_group_id = azurerm_network_security_group.k8s.id
}

# ---------------------------------------------------------------
# Linux VMs (1 master + 2 workers)
# ---------------------------------------------------------------
module "linux" {
  source = "../modules/resources/azure/linux-server"

  location              = module.resource_group.rs_group_location
  network_interface_ids = module.nic.nic_id
  node_count            = length(local.node_name)
  node_name             = local.node_name
  node_size             = local.vm_size
  os_disk_size          = local.os_disk_size
  zones                 = local.av_zones
  resource_group        = module.resource_group.rs_group_name
  username              = var.username
  ssh_public_key        = tls_private_key.ssh.public_key_openssh
  tags                  = local.common_tags
}

# ---------------------------------------------------------------
# Generate Ansible inventory from template
# ---------------------------------------------------------------
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/ansible/inventory.tpl", {
    master_name        = local.master_name
    master_public_ip   = azurerm_public_ip.k8s[0].ip_address
    master_private_ip  = module.nic.nic_private_ip[0]
    worker_names       = local.worker_names
    worker_public_ips  = slice(azurerm_public_ip.k8s[*].ip_address, 1, length(local.node_name))
    worker_private_ips = slice(module.nic.nic_private_ip, 1, length(local.node_name))
    ssh_user           = var.username
    letsencrypt_email  = var.letsencrypt_email
    use_staging_issuer = var.use_staging_issuer
  })
  filename = "${path.module}/ansible/inventory.ini"

  depends_on = [module.linux]
}

# ---------------------------------------------------------------
# Wait for SSH readiness on all VMs before Ansible runs
# ---------------------------------------------------------------
resource "null_resource" "wait_for_ssh" {
  count = length(local.node_name)

  triggers = {
    vm_id = module.linux.node_id[count.index]
  }

  provisioner "local-exec" {
    command = "ansible -i '${azurerm_public_ip.k8s[count.index].ip_address},' -u ${var.username} --private-key ~/ssh_key.pem -o -m wait_for_connection -a 'timeout=300' all"

    environment = {
      ANSIBLE_HOST_KEY_CHECKING = "False"
      ANSIBLE_SSH_ARGS          = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    }
  }

  depends_on = [
    module.linux,
    local_sensitive_file.ssh_private_key,
    azurerm_network_interface_security_group_association.k8s
  ]
}

# ---------------------------------------------------------------
# Run Ansible to configure K8s cluster
# ---------------------------------------------------------------
resource "null_resource" "ansible_k8s" {
  triggers = {
    vm_ids = join(",", module.linux.node_id)
  }

  provisioner "local-exec" {
    working_dir = "${path.module}/ansible"
    command     = "ansible-playbook -i inventory.ini site.yml"

    environment = {
      ANSIBLE_HOST_KEY_CHECKING = "False"
    }
  }

  depends_on = [
    module.linux,
    local_file.ansible_inventory,
    local_sensitive_file.ssh_private_key,
    azurerm_network_interface_security_group_association.k8s,
    null_resource.wait_for_ssh
  ]
}
