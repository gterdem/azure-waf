# Terraform Configuration — Azure WAF Project

This directory contains all Infrastructure as Code (IaC) for the Cloud-Based WAF project. Every Azure resource is defined here and can be created with `terraform apply` or destroyed with `terraform destroy`.

---

## Quick Start

```bash
# First time setup
cd terraform/
terraform init                    # Download Azure provider (~200MB, one time only)
terraform plan                    # Preview what will be created
terraform apply                   # Deploy everything (type "yes" to confirm)
or
terraform apply -auto-approve     # Auto approves without user input 

# When done for the day — IMPORTANT!
terraform destroy                 # Tear down everything to stop billing
or 
terraform destroy -auto-approve   # Auto approves without user input
# See what's running
terraform output                  # Show public IP, VM details, etc.
terraform state list              # List all managed resources
```

---

## File Overview

```
terraform/
├── main.tf              # Provider configuration + resource group
├── variables.tf         # All configurable values (region, VM size, CIDRs, etc.)
├── outputs.tf           # Values displayed after deploy (public IP, URLs, etc.)
├── network.tf           # Virtual network, subnets, network security group
├── compute.tf           # 2 Ubuntu VMs with automatic Juice Shop installation
├── appgateway.tf        # Application Gateway (load balancer + WAF entry point)
├── waf-policy.tf        # WAF rules — managed (OWASP CRS 3.2) + custom rules
├── terraform.tfvars     # YOUR personal values (gitignored — never committed)
└── terraform.tfvars.example  # Template for terraform.tfvars
```

---

## File-by-File Explanation

### main.tf — Provider & Resource Group

**What it does:** Configures Terraform to use Azure and creates the resource group that contains everything.

**Key resources:**
- `azurerm` provider — tells Terraform to use the Azure Resource Manager API
- `azurerm_resource_group.main` — a logical container for all project resources. Like a folder in Azure — when you delete the resource group, everything inside is deleted too.

**Important setting:**
```hcl
resource_provider_registrations = "none"
```
Azure for Students subscriptions can't auto-register resource providers (causes 409 errors). This setting tells Terraform to skip auto-registration. We register providers manually once with `az provider register` — see the project README.

**Tags:**
```hcl
tags = {
  project     = "Azure-WAF-Project"
  environment = "staging"
}
```
Tags are metadata labels. They don't affect functionality — they help you identify and filter resources in the Azure Portal and Cost Management. All resources inherit these tags for consistency.

---

### variables.tf — Configuration Values

**What it does:** Defines every value that might change between deployments. Instead of hardcoding "canadacentral" everywhere, we define it once as a variable and reference it as `var.location`.

**Why variables matter for reproducibility:** When someone clones the repo, they only need to change values in `terraform.tfvars` — not edit the Terraform code itself.

| Variable | Default | Purpose |
|---|---|---|
| `subscription_id` | (none — required) | Your Azure subscription ID |
| `resource_group_name` | `rg-waf-project` | Name for the resource group |
| `location` | `canadacentral` | Azure region — closest to Toronto |
| `vnet_address_space` | `10.0.0.0/16` | VNet IP range (65,536 addresses) |
| `subnet_appgw_prefix` | `10.0.0.0/24` | App Gateway subnet (256 addresses) |
| `subnet_backend_prefix` | `10.0.1.0/24` | Backend VM subnet (256 addresses) |
| `vm_size` | `Standard_B1s` | VM size — cheapest option (1 vCPU, 1GB RAM) |
| `vm_admin_username` | `azureuser` | SSH username for the VMs |
| `allowed_ssh_ip` | (none — required) | Your public IP for SSH access |
| `vm_zones` | `["2", "3"]` | Availability zones for the VMs |

**Customization:** If Zone 2 or 3 has capacity issues, change `vm_zones` in your `terraform.tfvars`:
```hcl
vm_zones = ["1", "3"]  # Use different zones if needed
```

---

### outputs.tf — Deployment Information

**What it does:** After `terraform apply` completes, Terraform prints these values. They tell you everything you need to access and manage the deployed infrastructure.

| Output | Example Value | What It Tells |
|---|---|---|
| `appgw_public_ip` | `20.151.132.106` | The IP address to access Juice Shop |
| `juice_shop_url` | `http://20.151.132.106` | Full URL — paste into browser |
| `waf_mode` | `Detection` | Current WAF mode (Detection or Prevention) |
| `vm_private_ips` | `["10.0.1.5", "10.0.1.4"]` | Internal IPs of the VMs (not internet-accessible) |
| `vm_names` | `["vm-web-01", "vm-web-02"]` | VM names for Azure CLI commands |
| `vm_zones` | `["2", "3"]` | Which availability zones the VMs are in |
| `resource_group_name` | `rg-waf-project` | Resource group name for Azure CLI |
| `vnet_name` | `vnet-waf-project` | VNet name |

**Usage in scripts:**
```bash
# Get just the public IP
terraform output -raw appgw_public_ip

# Use in curl commands
curl http://$(terraform output -raw appgw_public_ip)/
```

---

### network.tf — Virtual Network & Security

**What it does:** Creates the isolated private network where all resources live, along with firewall rules controlling what traffic is allowed.

**Key resources:**

**`azurerm_virtual_network.main`** — The Virtual Network (VNet)
- Address space: `10.0.0.0/16` (65,536 private IP addresses)
- This is our isolated network. Nothing inside is reachable from the internet unless we explicitly create a path (like the Application Gateway's public IP).

**`azurerm_subnet.appgw`** — Application Gateway Subnet (`10.0.0.0/24`)
- Azure **requires** the Application Gateway to live in its own dedicated subnet with no other resources. This is a hard Azure requirement, not a design choice.
- 256 addresses — more than enough for the gateway instances.

**`azurerm_subnet.backend`** — Backend Subnet (`10.0.1.0/24`)
- Where the 2 Juice Shop VMs live.
- No public IPs — VMs are only reachable through the Application Gateway or via SSH from the admin IP.

**`azurerm_network_security_group.backend`** — Network Security Group (NSG)
- A subnet-level firewall. Three rules:

| Priority | Name | What It Allows | Why |
|---|---|---|---|
| 100 | Allow-AppGW-to-Backend | AppGW subnet → port 3000 | WAF-inspected traffic to Juice Shop |
| 110 | Allow-SSH-Admin | Your IP → port 22 | SSH for setup/troubleshooting |
| 120 | Allow-AppGW-Health | GatewayManager → ports 65200-65535 | App Gateway health probes (required by Azure) |
| 65500 | (implicit) | Deny everything else | Azure adds this automatically |

**`azurerm_subnet_network_security_group_association.backend`**
- Attaches the NSG to the backend subnet. Creating an NSG alone doesn't protect anything — you must explicitly associate it.

**Security principle:** Defense in depth. Even if an attacker somehow bypassed the WAF, the NSG blocks them from reaching the VMs on any port except 3000 from the AppGW subnet.

---

### compute.tf — Virtual Machines

**What it does:** Creates 2 Ubuntu VMs that automatically install Docker and run OWASP Juice Shop on startup.

**Key components:**

**`local.cloud_init`** — The startup script
- This is a bash script that runs automatically the first time each VM boots (via cloud-init, a standard Linux initialization system).
- It installs Docker, enables it to start on boot, and runs the Juice Shop container on port 3000.
- This means the deployment is fully automated — no need to SSH in and manually install anything.

**`azurerm_network_interface.web`** — Network Interface Cards (2x)
- Each VM needs a NIC to connect to the backend subnet.
- `count = 2` creates two NICs in a single resource block.
- No `public_ip_address_id` — intentionally private only.

**`azurerm_linux_virtual_machine.web`** — The VMs (2x)
- `count = 2` creates two identical VMs.
- `Standard_B1s` — cheapest Azure VM (1 vCPU, 1 GB RAM, ~$0.01/hr).
- `zone = var.vm_zones[count.index]` — places each VM in a different availability zone (physically separate data centers). Satisfies the multi-AZ rubric requirement.
- `admin_ssh_key` — uses your SSH public key for authentication (no passwords).
- `custom_data` — passes the cloud-init script (base64 encoded) to the VM.

**`lifecycle { ignore_changes = [custom_data] }`**
- Azure doesn't store cloud-init data back into Terraform state. If you ever import a VM (e.g., after a state issue), Terraform would see "custom_data changed from null to (script)" and try to replace the VM.
- `ignore_changes` prevents this. On a fresh `terraform apply`, cloud-init still runs normally — this only affects re-imported VMs.

**If B1s is too slow:** Change `vm_size` in `terraform.tfvars`:
```hcl
vm_size = "Standard_B1ms"  # 2 GB RAM instead of 1 GB
```

---

### appgateway.tf — Application Gateway

**What it does:** Creates the Application Gateway, which is the core component — it acts as both the **Web Application Firewall** and the **Layer 7 Load Balancer** in a single resource.

**Key resources:**

**`azurerm_public_ip.appgw`** — The Public IP
- Standard SKU, Static allocation (required for WAF_v2).
- This is the **only** internet-facing IP in the entire architecture.
- All traffic enters here → gets inspected by the WAF → forwarded to VMs.

**`azurerm_application_gateway.main`** — The Gateway
- This is the most complex Terraform resource because it configures the entire traffic path in nested blocks:

```
Internet → [Frontend IP + Port] → [Listener] → [Routing Rule] → [Backend Pool + HTTP Settings]
                                                                          ↕
                                                                   [Health Probes]
```

| Block | Purpose |
|---|---|
| `sku` | WAF_v2 tier — required for custom rules, autoscaling, and CRS 3.2 |
| `autoscale_configuration` | Min 1, max 2 instances. Saves cost (min 1) while allowing scale-up (max 2). Satisfies the "scalability" rubric requirement. |
| `gateway_ip_configuration` | Links the gateway to the AppGW subnet. Azure requires this dedicated subnet. |
| `frontend_ip_configuration` | Links the public IP to the gateway. This is what users connect to. |
| `frontend_port` | Port 80 (HTTP). Users hit this port from the internet. |
| `http_listener` | Listens for incoming requests on the frontend IP + port. When a request arrives, hands it to the routing rule. |
| `backend_address_pool` | The 2 VM private IPs (10.0.1.4, 10.0.1.5). Gateway distributes traffic between them. |
| `backend_http_settings` | How the gateway talks to VMs: port 3000, HTTP, 30s timeout. Port translation happens here — users hit port 80, gateway forwards to port 3000. |
| `probe` | Health check — HTTP GET to `/` on port 3000 every 30 seconds. If a VM fails 3 checks in a row, it's removed from the pool. Auto-recovery when it responds again. |
| `request_routing_rule` | Connects listener → backend pool. "Take requests from port 80 and send them to the VMs on port 3000." |
| `firewall_policy_id` | Links the WAF policy (from waf-policy.tf). All traffic is inspected by the WAF before reaching VMs. |

---

### waf-policy.tf — WAF Rules

**What it does:** Defines which attacks the WAF detects/blocks. This is the security brain of the architecture.

**Key resource:**

**`azurerm_web_application_firewall_policy.main`**

**Policy Settings:**
- `mode = "Detection"` — we start here. Logs attacks but doesn't block them. This lets us identify false positives (legitimate traffic incorrectly flagged as attacks) before enabling blocking.
- After tuning, we change to `mode = "Prevention"` to actively block attacks.

**Managed Rules — OWASP CRS 3.2:**
```hcl
managed_rules {
  managed_rule_set {
    type    = "OWASP"
    version = "3.2"
  }
}
```
These are ~150+ pre-built detection rules maintained by Microsoft. They cover SQL injection, XSS, command injection, file inclusion, and more. All rules are enabled by default — we add exclusions during tuning if we find false positives.

CRS 3.2 uses **anomaly scoring**: each rule match adds points (Critical=5, Error=4, Warning=3, Notice=2). A request is blocked when the total score reaches 5 or higher. A single Critical match blocks immediately.

**Microsoft Bot Manager:**
```hcl
managed_rule_set {
  type    = "Microsoft_BotManagerRuleSet"
  version = "1.0"
}
```
Detects and blocks known bad bots (vulnerability scanners, scrapers) while allowing good bots (Googlebot, Bingbot).

**Custom Rule 1 — Geo-Blocking (Priority 1):**
- Blocks any request where the source country is NOT Canada or US.
- `negation_condition = true` means "block if NOT matching" — so we specify allowed countries and negate.
- Priority 1 because geo-checking is the cheapest operation — reject irrelevant traffic before expensive payload inspection.
- For this project, there's no reason for international traffic to access Juice Shop.

**Custom Rule 2 — Rate Limiting (Priority 2):**
- Blocks any IP that sends more than 100 requests in 1 minute.
- Prevents brute-force attacks, credential stuffing, and application-layer DDoS.
- Normal browsing generates ~10-20 requests per minute, so legitimate users are unaffected.
- `group_rate_limit_by = "ClientAddr"` means each IP gets its own counter.

**Custom Rule 3 — IP Reputation Blocking (Priority 3):**
- Blocks specific IP addresses known to be malicious.
- The `match_values` list contains sample Tor exit node IPs.
- **These IPs should be updated before testing** — see "Updating the IP List" below.

### Updating the IP Reputation List

The IPs in the `match_values` list are TOR exit nodes IPs from  current Tor exit node IPs:

```bash
# Current Tor exit nodes
curl -s https://raw.githubusercontent.com/SecOps-Institute/Tor-IP-Addresses/master/tor-exit-nodes.lst | head -15
```

They are added to `match_values` list in `waf-policy.tf` to prevent anonymous access by TOR.

## Important!
During testing, **we will temporarily add our own public IP to this list to prove the rule works,** then remove it.


---

## How Resources Connect

```
main.tf (resource group)
  └── network.tf
  │     ├── VNet
  │     ├── Subnet: AppGW ──────────────────────────┐
  │     ├── Subnet: Backend ──────────────────┐      │
  │     ├── NSG (attached to backend subnet)  │      │
  │     │                                     │      │
  └── compute.tf                              │      │
  │     ├── NIC × 2 (connected to backend) ───┘      │
  │     ├── VM × 2 (using NICs, cloud-init)          │
  │     │                                            │
  └── appgateway.tf                                  │
  │     ├── Public IP                                │
  │     ├── Application Gateway (in AppGW subnet) ───┘
  │     │     ├── Frontend: Public IP, port 80
  │     │     ├── Backend Pool: VM private IPs, port 3000
  │     │     ├── Health Probes: check VMs every 30s
  │     │     └── WAF Policy link ──────────────┐
  │     │                                       │
  └── waf-policy.tf                             │
        ├── Managed Rules (OWASP CRS 3.2) ──────┘
        ├── Bot Manager Rules
        └── Custom Rules (Geo-block, Rate limit, IP reputation)
```

---

## Cost Management

| Resource | Hourly Cost | Notes |
|---|---|---|
| Application Gateway WAF_v2 | ~$0.36/hr | **Most expensive — cannot be paused** |
| 2× VMs (B1s) | ~$0.02/hr total | Very cheap |
| Public IP (Standard) | ~$0.005/hr | Minimal |
| VNet, Subnets, NSGs | $0 | Free |
| Log Analytics | Per GB ingested | Negligible |
| **Total while running** | **~$0.39/hr** | |

**Golden rule:** `terraform destroy` when done for the day. `terraform apply` when ready to work again. Everything rebuilds identically in **~12-15 minutes**.

---

## Troubleshooting

**`ZonalAllocationFailed`** — Azure has no capacity for B1s in the requested zone.
- **Fix:** Change `vm_zones` in `terraform.tfvars` to different zones (e.g., `["1", "3"]` or `["2", "3"]`).

**`ConflictingConcurrentWriteNotAllowed`** — Azure resource provider registration throttled.
- **Fix:** Already handled by `resource_provider_registrations = "none"` in main.tf. Providers are registered manually once.

**VMs show Unhealthy in backend pool** — Cloud-init hasn't finished yet.
- Fix: Wait 3-4 minutes after `terraform apply`. Juice Shop Docker image takes time to download.

**`terraform import` needed after state issues** — VM exists in Azure but not in Terraform state.
- **Fix:** 
```
terraform import "azurerm_linux_virtual_machine.web[0]" "/subscriptions/.../virtualMachines/vm-web-01"
```
- The `lifecycle { ignore_changes = [custom_data] }` block prevents replacement after import.

**`Already exists`** — error for diagnostic setting: is a known Azure behavior — diagnostic settings can survive resource group deletion. 
```
Error: a resource with the ID "/subscriptions/<YOUR_SUB_ID>/resourceGroups/rg-waf-project/providers/Microsoft.Network/applicationGateways/appgw-waf|diag-appgw-to-law" already exists - to be managed via Terraform this resource needs to be imported into the State. Please see the resource documentation for "azurerm_monitor_diagnostic_setting" for more information
│
│   with azurerm_monitor_diagnostic_setting.appgw,
│   on monitoring.tf line 28, in resource "azurerm_monitor_diagnostic_setting" "appgw":
│   28: resource "azurerm_monitor_diagnostic_setting" "appgw" {
```
- **Fix:** 
```bash
terraform import azurerm_monitor_diagnostic_setting.appgw "/subscriptions/<YOUR_SUB_ID>/resourceGroups/rg-waf-project/providers/Microsoft.Network/applicationGateways/appgw-waf|diag-appgw-to-law" 
```
then terraform apply.