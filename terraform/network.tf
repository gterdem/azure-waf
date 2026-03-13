# ──────────────────────────────────────────────
# Virtual Network
# ──────────────────────────────────────────────
# The VNet is our isolated private network in Azure.
# All resources (App Gateway, VMs) live inside this network.
# Nothing inside is internet-accessible unless we explicitly allow it.

resource "azurerm_virtual_network" "main" {
  name                = "vnet-waf-project"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = [var.vnet_address_space] # 10.0.0.0/16 — 65,536 addresses

  tags = azurerm_resource_group.main.tags
}

# ──────────────────────────────────────────────
# Subnet: Application Gateway
# ──────────────────────────────────────────────
# Azure REQUIRES the Application Gateway to have its own dedicated subnet.
# No other resources can be placed here — only the gateway.
# /24 gives us 256 addresses, which is more than enough.

resource "azurerm_subnet" "appgw" {
  name                 = "subnet-appgw"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_appgw_prefix] # 10.0.0.0/24
}

# ──────────────────────────────────────────────
# Subnet: Backend (Web Servers)
# ──────────────────────────────────────────────
# This is where our 2 Juice Shop VMs live.
# No public IPs — only reachable through the Application Gateway
# or via SSH from our admin IP.

resource "azurerm_subnet" "backend" {
  name                 = "subnet-backend"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_backend_prefix] # 10.0.1.0/24
}

# ──────────────────────────────────────────────
# Network Security Group (NSG) — Backend Subnet
# ──────────────────────────────────────────────
# Acts as a subnet-level firewall. Controls what traffic
# can reach the VMs. Defense in depth — even if someone
# bypassed the WAF, the NSG blocks unauthorized access.

resource "azurerm_network_security_group" "backend" {
  name                = "nsg-backend"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Rule 1: Allow traffic from App Gateway subnet on port 3000
  # This is the ONLY way web traffic reaches the VMs —
  # through the WAF, which has already inspected it.
  security_rule {
    name                       = "Allow-AppGW-to-Backend"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3000"
    source_address_prefix      = var.subnet_appgw_prefix # 10.0.0.0/24
    destination_address_prefix = var.subnet_backend_prefix # 10.0.1.0/24
  }

  # Rule 2: Allow SSH from our IP only
  # For initial setup and troubleshooting.
  # In production, you'd use Azure Bastion instead.
  security_rule {
    name                       = "Allow-SSH-Admin"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.allowed_ssh_ip
    destination_address_prefix = var.subnet_backend_prefix
  }

  # Rule 3: Allow App Gateway health probes
  # Azure Application Gateway sends health probes from the
  # GatewayManager service tag. Without this, the gateway
  # can't check if VMs are healthy and won't route traffic.
  security_rule {
    name                       = "Allow-AppGW-Health"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  # Everything else is denied by Azure's implicit deny rule (priority 65500)
  # We don't need to write it — Azure adds it automatically.

  tags = azurerm_resource_group.main.tags
}

# ──────────────────────────────────────────────
# Associate NSG with Backend Subnet
# ──────────────────────────────────────────────
# Creating an NSG doesn't automatically protect anything.
# We must explicitly attach it to the subnet.

resource "azurerm_subnet_network_security_group_association" "backend" {
  subnet_id                 = azurerm_subnet.backend.id
  network_security_group_id = azurerm_network_security_group.backend.id
}