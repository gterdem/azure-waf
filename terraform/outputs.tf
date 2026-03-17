# ──────────────────────────────────────────────
# Outputs — Displayed after terraform apply
# ──────────────────────────────────────────────

output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "location" {
  value = azurerm_resource_group.main.location
}

output "vnet_name" {
  value = azurerm_virtual_network.main.name
}

output "subnet_appgw_id" {
  value = azurerm_subnet.appgw.id
}

output "subnet_backend_id" {
  value = azurerm_subnet.backend.id
}

output "nsg_backend_name" {
  value = azurerm_network_security_group.backend.name
}

output "vm_private_ips" {
  description = "Private IPs of the backend VMs"
  value       = azurerm_network_interface.web[*].private_ip_address
}

output "vm_names" {
  description = "Names of the backend VMs"
  value       = azurerm_linux_virtual_machine.web[*].name
}

output "vm_zones" {
  description = "Availability zones of the VMs"
  value       = azurerm_linux_virtual_machine.web[*].zone
}

# ── This is the URL you'll use to access Juice Shop ──
output "appgw_public_ip" {
  description = "Public IP of the Application Gateway — access Juice Shop here"
  value       = azurerm_public_ip.appgw.ip_address
}

output "juice_shop_url" {
  description = "URL to access Juice Shop through the WAF"
  value       = "http://${azurerm_public_ip.appgw.ip_address}"
}

output "waf_mode" {
  description = "Current WAF mode"
  value       = azurerm_web_application_firewall_policy.main.policy_settings[0].mode
}

output "log_analytics_workspace_name" {
  description = "Log Analytics Workspace name"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID (for KQL queries)"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}