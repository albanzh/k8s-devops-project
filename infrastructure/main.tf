locals {
  rsname       = "rg_es_kube_test"
  vnet_name    = "vnet_es_kube_test"
  vnet_rg      = "rg_es_kube_test"
  vm_subnet    = "snet_es_kube_test"
  os_disk_size = 127
  av_zones     = false

  # ─── Per-role VM sizing ───────────────────────────────────────────
  master_size = "Standard_D4s_v3"   # 4 vCPU, 16 GB
  worker_size = "Standard_D2s_v3"      # 2 vCPU, 4 GB

  # ─── Cluster nodes ────────────────────────────────────────────────
  master_name  = "k8s-master"
  worker_names = ["k8s-worker-1", "k8s-worker-2"]
  node_name    = concat([local.master_name], local.worker_names)

  node_size = concat(
    [local.master_size],
    [for _ in local.worker_names : local.worker_size]
  )

  # ─── OS image (Ubuntu 22.04 LTS Gen2) ─────────────────────────────
  image_publisher = "Canonical"
  image_offer     = "0001-com-ubuntu-server-jammy"
  image_sku       = "22_04-lts-gen2"
  image_version   = "latest"

  # ─── NSG rules — single source of truth ───────────────────────────
  # SSH + K8s API restricted to admin_source_cidr.
  # HTTP/HTTPS public so ingress works.
  # Intra-cluster ports scoped to VirtualNetwork.
  nsg_rules = [
    { name = "SSH-admin",      priority = 100, destination_port_range = "22",       source_address_prefixes = var.admin_source_cidr },
    { name = "HTTP-public",    priority = 110, destination_port_range = "80",       source_address_prefix   = "*" },
    { name = "HTTPS-public",   priority = 120, destination_port_range = "443",      source_address_prefix   = "*" },
    { name = "K8s-API-admin",  priority = 130, destination_port_range = "6443",     source_address_prefixes = var.admin_source_cidr },
    { name = "Kubelet-API",    priority = 150, destination_port_range = "10250",    source_address_prefix   = "VirtualNetwork" },
    { name = "Calico-VXLAN",   priority = 160, destination_port_range = "4789",     source_address_prefix   = "VirtualNetwork", protocol = "Udp" },
    { name = "Calico-BGP",     priority = 170, destination_port_range = "179",      source_address_prefix   = "VirtualNetwork" },
    { name = "ETCD",           priority = 180, destination_port_range = "2379-2380", source_address_prefix   = "VirtualNetwork" },
  ]

  common_tags = {
    environment = "demo"
    project     = "k8s-bookstore"
    managed_by  = "terraform"
  }
}

# ─── SSH key (private file written to ~/ssh_key.pem) ────────────────
module "ssh" {
  source           = "../modules/resources/azure/ssh-key"
  private_key_path = "~/ssh_key.pem"
}

# ─── Data sources (existing RG + Subnet) ────────────────────────────
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

# ─── Public IPs (one per node) ──────────────────────────────────────
module "public_ip" {
  source              = "../modules/resources/azure/public-ip"
  names               = local.node_name
  location            = module.resource_group.rs_group_location
  resource_group_name = module.resource_group.rs_group_name
  tags                = local.common_tags
}

# ─── NSG (rules from local.nsg_rules) ───────────────────────────────
module "nsg" {
  source              = "../modules/resources/azure/nsg"
  name                = "k8s-nsg"
  location            = module.resource_group.rs_group_location
  resource_group_name = module.resource_group.rs_group_name
  tags                = local.common_tags
  rules               = local.nsg_rules
}

# ─── NICs (with public IPs) ─────────────────────────────────────────
module "nic" {
  source         = "../modules/resources/azure/network-interface"
  nic_count      = length(local.node_name)
  location       = module.resource_group.rs_group_location
  name           = local.node_name
  resource_group = module.resource_group.rs_group_name
  subnet_id      = module.linux_subnet.subnet_id
  public_ip_ids  = module.public_ip.ids
  tags           = local.common_tags
}

# ─── Bind NSG to each NIC ───────────────────────────────────────────
# Too thin for its own module (one resource, no logic).
resource "azurerm_network_interface_security_group_association" "k8s" {
  count                     = length(local.node_name)
  network_interface_id      = module.nic.nic_id[count.index]
  network_security_group_id = module.nsg.id
}

# ─── Public Load Balancer (HA in front of all 3 nodes) ──────────────
# DuckDNS points here — survives master VM destroy/recreate.
# Health probes auto-remove failed nodes from the pool.
module "lb" {
  source              = "../modules/resources/azure/load-balancer"
  name                = "k8s-lb"
  location            = module.resource_group.rs_group_location
  resource_group_name = module.resource_group.rs_group_name
  backend_nic_ids     = module.nic.nic_id
  ports               = [80, 443]   # HTTP + HTTPS for ingress
  tags                = local.common_tags

  # Each VM has its own public IP for SSH + outbound, so don't add an outbound
  # rule on the LB (would cause double-NAT).
  enable_outbound_rule = false
}

# ─── Linux VMs (1 master + 2 workers) ───────────────────────────────
module "linux" {
  source = "../modules/resources/azure/linux-server"

  location              = module.resource_group.rs_group_location
  network_interface_ids = module.nic.nic_id
  node_count            = length(local.node_name)
  node_name             = local.node_name
  node_size             = local.node_size
  os_disk_size          = local.os_disk_size
  zones                 = local.av_zones
  resource_group        = module.resource_group.rs_group_name
  username              = var.username
  ssh_public_key        = module.ssh.public_key_openssh
  tags                  = local.common_tags

  image_publisher = local.image_publisher
  image_offer     = local.image_offer
  image_sku       = local.image_sku
  image_version   = local.image_version
}

# ─── Generate Ansible inventory from template ───────────────────────
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/ansible/inventory.tpl", {
    master_name        = local.master_name
    master_public_ip   = module.public_ip.ip_addresses[0]
    master_private_ip  = module.nic.nic_private_ip[0]
    worker_names       = local.worker_names
    worker_public_ips  = slice(module.public_ip.ip_addresses, 1, length(local.node_name))
    worker_private_ips = slice(module.nic.nic_private_ip, 1, length(local.node_name))
    ssh_user           = var.username
    letsencrypt_email  = var.letsencrypt_email
    use_staging_issuer = var.use_staging_issuer
  })
  filename = "${path.module}/ansible/inventory.ini"

  depends_on = [module.linux]
}

# ─── Wait for SSH readiness on all VMs before Ansible runs ──────────
resource "null_resource" "wait_for_ssh" {
  count = length(local.node_name)

  triggers = {
    vm_id = module.linux.node_id[count.index]
  }

  provisioner "local-exec" {
    command = "ansible -i '${module.public_ip.ip_addresses[count.index]},' -u ${var.username} --private-key ~/ssh_key.pem -o -m wait_for_connection -a 'timeout=300' all"

    environment = {
      ANSIBLE_HOST_KEY_CHECKING = "False"
      ANSIBLE_SSH_ARGS          = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    }
  }

  depends_on = [
    module.linux,
    module.ssh,
    azurerm_network_interface_security_group_association.k8s
  ]
}

# ─── Run Ansible to configure K8s cluster ───────────────────────────
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
    module.ssh,
    azurerm_network_interface_security_group_association.k8s,
    null_resource.wait_for_ssh
  ]
}
