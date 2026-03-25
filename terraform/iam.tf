# ──────────────────────────────────────────────
# IAM — Teammate Access
# ──────────────────────────────────────────────
# Grant Reader access to teammates so they can view resources,
# run KQL queries, and check WAF logs in Azure Portal.
# Recreated automatically on every terraform apply.

resource "azurerm_role_assignment" "thomas" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Reader"
  principal_id         = "105ff23e-8723-4dfb-a09b-8cd1a531c144"
}

resource "azurerm_role_assignment" "david" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Reader"
  principal_id         = "87a27b63-3134-4b19-a08a-b9bd5d5125ea"
}

resource "azurerm_role_assignment" "jeremy" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Reader"
  principal_id         = "3e99a5a3-7c2e-4511-9c8a-9d86602ea27a"
}
