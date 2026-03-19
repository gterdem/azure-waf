# ──────────────────────────────────────────────
# Log Analytics Workspace
# ──────────────────────────────────────────────
# Central log storage and query engine.
# All WAF logs flow here and become queryable via KQL.
# This is where dashboard data, FireWatch queries, and
# all attack evidence comes from.

resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-waf-project"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018" # Pay per GB ingested — cheapest for low volume
  retention_in_days   = 30          # Keep logs for 30 days

  tags = azurerm_resource_group.main.tags
}

# ──────────────────────────────────────────────
# Diagnostic Settings — Application Gateway
# ──────────────────────────────────────────────
# Tells Azure to send Application Gateway logs to Log Analytics.
# Three log categories:
#   - Firewall Log: every WAF rule match (blocked/detected)
#   - Access Log: every HTTP request (allowed + blocked)
#   - Performance Log: backend health, latency, throughput

resource "azurerm_monitor_diagnostic_setting" "appgw" {
  name                       = "diag-appgw-to-law"
  target_resource_id         = azurerm_application_gateway.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "ApplicationGatewayFirewallLog"
  }

  enabled_log {
    category = "ApplicationGatewayAccessLog"
  }

  enabled_log {
    category = "ApplicationGatewayPerformanceLog"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}