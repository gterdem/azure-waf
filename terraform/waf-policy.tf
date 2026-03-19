# ──────────────────────────────────────────────
# WAF Policy
# ──────────────────────────────────────────────
# The WAF policy defines which rules are active and how they behave.
# It's a separate resource from the Application Gateway so it can be
# updated independently (e.g., switching modes) without recreating the gateway.

resource "azurerm_web_application_firewall_policy" "main" {
  name                = "wafpolicy-waf-project"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # ── Policy Settings ──
  policy_settings {
    enabled                     = true
    mode                        = "Prevention"
    request_body_check          = true
    max_request_body_size_in_kb = 128
    file_upload_limit_in_mb     = 100
  }

  # ── Managed Rules ──
  managed_rules {

    managed_rule_set {
      type    = "OWASP"
      version = "3.2"

      # Disable rule 920350: "Host header is a numeric IP address"
      # We access Juice Shop via IP (no domain name in a student project),
      # so every request triggers this rule. This is a known false positive
      # when using IP-based access instead of a domain name.
      rule_group_override {
        rule_group_name = "REQUEST-920-PROTOCOL-ENFORCEMENT"
        rule {
          id      = "920350"
          enabled = false
        }
      }
    }

    # Microsoft Bot Manager — detects and blocks known bad bots
    managed_rule_set {
      type    = "Microsoft_BotManagerRuleSet"
      version = "1.0"
    }

  }

  # ── Custom Rule 1: Geo-Blocking (Priority 1) ──
  custom_rules {
    name      = "GeoBlockRule"
    priority  = 1
    rule_type = "MatchRule"
    action    = "Block"

    match_conditions {
      match_variables {
        variable_name = "RemoteAddr"
      }
      operator           = "GeoMatch"
      negation_condition = true
      match_values       = ["CA", "US"]
    }
  }

  # ── Custom Rule 2: Rate Limiting (Priority 2) ──
  custom_rules {
    name                 = "RateLimitRule"
    priority             = 2
    rule_type            = "RateLimitRule"
    action               = "Block"
    rate_limit_duration  = "OneMin"
    rate_limit_threshold = 100
    group_rate_limit_by  = "ClientAddr"

    match_conditions {
      match_variables {
        variable_name = "RemoteAddr"
      }
      operator           = "IPMatch"
      negation_condition = true
      match_values       = ["127.0.0.1"]
    }
  }

  # ── Custom Rule 3: IP Reputation Blocking (Priority 3) ──
  custom_rules {
    name      = "IPReputationBlock"
    priority  = 3
    rule_type = "MatchRule"
    action    = "Block"

    match_conditions {
      match_variables {
        variable_name = "RemoteAddr"
      }
      operator     = "IPMatch"
      match_values = [
        # Sample Tor exit node IPs (replace with current ones from
        #  curl -s https://raw.githubusercontent.com/SecOps-Institute/Tor-IP-Addresses/master/tor-exit-nodes.lst | head -15)
        "101.99.92.179",
        "101.99.92.182",
        "101.99.92.194",
        "101.99.92.198",
        "102.130.113.9",
        "102.130.127.117",
        "103.106.3.94",
        "103.109.101.105",
        "103.126.161.54",
        "103.129.222.46",
        "103.163.218.11",
        "103.172.134.26",
        "103.193.179.233",
        "103.196.37.111",
        "103.208.86.5"
      ]
    }
  }

  tags = azurerm_resource_group.main.tags
}