# ──────────────────────────────────────────────
# Variables — Change these in terraform.tfvars
# ──────────────────────────────────────────────

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-waf-project"
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "canadacentral"
}

variable "vnet_address_space" {
  description = "VNet CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_appgw_prefix" {
  description = "App Gateway subnet CIDR"
  type        = string
  default     = "10.0.0.0/24"
}

variable "subnet_backend_prefix" {
  description = "Backend subnet CIDR"
  type        = string
  default     = "10.0.1.0/24"
}

variable "vm_size" {
  description = "VM size for web servers"
  type        = string
  default     = "Standard_B1s"
}

variable "vm_admin_username" {
  description = "Admin username for VMs"
  type        = string
  default     = "azureuser"
}

variable "allowed_ssh_ip" {
  description = "Your public IP for SSH access"
  type        = string
}

variable "vm_zones" {
  description = "Availability zones for the 2 web VMs. Change if a zone has capacity issues."
  type        = list(string)
  default     = ["2", "3"]
}

variable "ssh_public_key_path" {
  description = "Path to your SSH public key file. Generate one with: ssh-keygen -t ed25519"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}