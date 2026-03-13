# ──────────────────────────────────────────────
# Public IP for Application Gateway
# ──────────────────────────────────────────────
# This is the ONLY internet-facing IP in our architecture.
# All traffic enters here and must pass through the WAF.
# Standard SKU is required for WAF_v2.

resource "azurerm_public_ip" "appgw" {
  name                = "pip-appgw"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static" # IP doesn't change while resource exists
  sku                 = "Standard" # Required for WAF_v2

  tags = azurerm_resource_group.main.tags
}

# ──────────────────────────────────────────────
# Application Gateway + WAF v2
# ──────────────────────────────────────────────
# This single resource acts as:
#   1. Web Application Firewall — inspects every request
#   2. Layer 7 Load Balancer — distributes traffic across VMs
#   3. Health checker — monitors backend VM availability
#
# The nested blocks below configure the full traffic path:
#   Frontend (public IP + port) → Listener → Routing Rule →
#   Backend Pool (VMs) ← Health Probes

resource "azurerm_application_gateway" "main" {
  name                = "appgw-waf"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # ── SKU: WAF_v2 ──
  # WAF_v2 is required for custom rules, autoscaling, and CRS 3.2.
  # We don't set fixed capacity here — autoscale_configuration handles that.
  sku {
    name = "WAF_v2"
    tier = "WAF_v2"
  }

  # ── Autoscale: Min 1, Max 2 ──
  # Min 1 saves cost when idle (instead of paying for 2 fixed instances).
  # Max 2 allows scaling up during load tests.
  # This satisfies the "scalability elements" rubric requirement.
  autoscale_configuration {
    min_capacity = 1
    max_capacity = 2
  }

  # ── Gateway IP Configuration ──
  # Tells the gateway which subnet it lives in.
  # This MUST be the dedicated AppGW subnet (Azure requirement).
  gateway_ip_configuration {
    name      = "gateway-ip-config"
    subnet_id = azurerm_subnet.appgw.id
  }

  # ── Frontend: Public IP ──
  # The internet-facing side of the gateway.
  # Users hit this IP → gateway inspects → forwards to backend.
  frontend_ip_configuration {
    name                 = "frontend-ip"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  # ── Frontend Port: 80 (HTTP) ──
  # The port users connect to. We use 80 (HTTP) for simplicity.
  # In production, port 443 (HTTPS) with a TLS certificate should be used.
  frontend_port {
    name = "frontend-port-http"
    port = 80
  }

  # ── HTTP Listener ──
  # Listens for incoming HTTP requests on the public IP, port 80.
  # When a request arrives, it's handed to the routing rule.
  http_listener {
    name                           = "listener-http"
    frontend_ip_configuration_name = "frontend-ip"
    frontend_port_name             = "frontend-port-http"
    protocol                       = "Http"
  }

  # ── Backend Pool ──
  # The 2 Juice Shop VMs. The gateway distributes traffic between them.
  # We reference their private IPs (no public IPs on the VMs).
  backend_address_pool {
    name         = "backend-pool"
    ip_addresses = azurerm_network_interface.web[*].private_ip_address
  }

  # ── Backend HTTP Settings ──
  # Tells the gateway HOW to talk to the backend VMs:
  # - Port 3000 (Juice Shop's port)
  # - HTTP protocol (not HTTPS to the backend)
  # - 30 second timeout
  backend_http_settings {
    name                  = "backend-http-settings"
    cookie_based_affinity = "Disabled" # Round-robin, no sticky sessions
    port                  = 3000
    protocol              = "Http"
    request_timeout       = 30
    probe_name            = "health-probe"
  }

  # ── Health Probe ──
  # The gateway checks each VM every 30 seconds by sending
  # an HTTP GET to "/" on port 3000. If a VM doesn't respond
  # 3 times in a row, it's marked unhealthy and removed from
  # the pool. When it recovers, it's automatically re-added.
  probe {
    name                = "health-probe"
    protocol            = "Http"
    host                = "127.0.0.1"
    path                = "/"
    interval            = 30 # Check every 30 seconds
    timeout             = 30 # Wait up to 30 seconds for response
    unhealthy_threshold = 3  # 3 failures = unhealthy
  }

  # ── Routing Rule ──
  # Connects everything together:
  # Listener (port 80) → Backend Pool (VMs on port 3000)
  # Priority 1 means this is the primary (and only) routing rule.
  request_routing_rule {
    name                       = "routing-rule"
    priority                   = 1
    rule_type                  = "Basic" # Simple: all traffic → one backend pool
    http_listener_name         = "listener-http"
    backend_address_pool_name  = "backend-pool"
    backend_http_settings_name = "backend-http-settings"
  }

  # ── Link WAF Policy ──
  # Attach the WAF policy we defined in waf-policy.tf.
  # All traffic through this gateway is inspected by the WAF.
  firewall_policy_id = azurerm_web_application_firewall_policy.main.id

  tags = azurerm_resource_group.main.tags
}