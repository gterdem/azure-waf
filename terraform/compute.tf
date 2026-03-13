# ──────────────────────────────────────────────
# Cloud-Init Script
# ──────────────────────────────────────────────
# cloud-init runs automatically on first boot.
# It installs Docker and starts OWASP Juice Shop
# so we don't have to SSH in and do it manually.
# This makes the deployment fully automated and reproducible.

locals {
  cloud_init = <<-CLOUDINIT
    #!/bin/bash
    set -e

    # Update package list and install Docker
    apt-get update -y
    apt-get install -y docker.io

    # Enable Docker to start on boot and start it now
    systemctl enable docker
    systemctl start docker

    # Run OWASP Juice Shop container
    # -d          : run in background
    # --restart always : restart if it crashes or VM reboots
    # -p 3000:3000    : expose port 3000 (Juice Shop's default)
    docker run -d \
      --name juice-shop \
      --restart always \
      -p 3000:3000 \
      bkimminich/juice-shop
  CLOUDINIT
}

# ──────────────────────────────────────────────
# Network Interfaces
# ──────────────────────────────────────────────
# Each VM needs a NIC (Network Interface Card) that
# connects it to the backend subnet. No public IPs —
# the VMs are only reachable through the App Gateway.

resource "azurerm_network_interface" "web" {
  count               = 2
  name                = "nic-web-${count.index + 1}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.backend.id
    private_ip_address_allocation = "Dynamic"
    # No public_ip_address_id — intentionally private only
  }

  tags = azurerm_resource_group.main.tags
}

# ──────────────────────────────────────────────
# Virtual Machines
# ──────────────────────────────────────────────
# 2 Ubuntu VMs, one in each Availability Zone.
# B1s is the cheapest size (~$0.01/hr each).
# cloud-init installs Juice Shop automatically on first boot.

resource "azurerm_linux_virtual_machine" "web" {
  count               = 2
  name                = "vm-web-0${count.index + 1}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Size: B1s = 1 vCPU, 1 GB RAM (~$0.01/hr)
  # If Juice Shop is too slow, change to Standard_B1ms (2 GB RAM)
  size = var.vm_size

  # Place VM-01 in AZ 1, VM-02 in AZ 2
  # This satisfies the multi-AZ rubric requirement
  zone = var.vm_zones[count.index]

  # Admin account — SSH key only, no password
  admin_username = var.vm_admin_username
  admin_ssh_key {
    username   = var.vm_admin_username
    public_key = file("~/.ssh/id_ed25519.pub")
  }
  disable_password_authentication = true

  # Connect to the backend subnet via the NIC
  network_interface_ids = [azurerm_network_interface.web[count.index].id]

  # Ubuntu 22.04 LTS — stable, well-supported, free
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # OS Disk — Standard SSD is cheapest
  os_disk {
    name                 = "osdisk-web-0${count.index + 1}"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  custom_data = base64encode(local.cloud_init)

  # cloud-init only runs on first boot. Azure does not store it in state,
  # so imported VMs always show a diff. This prevents unnecessary replacement.
  # On a fresh terraform apply, custom_data still works normally.
  lifecycle {
    ignore_changes = [custom_data]
  }

  tags = azurerm_resource_group.main.tags
}