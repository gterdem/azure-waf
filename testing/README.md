# Testing Plan — Cloud-Based Web Application Firewall

**Project:** Azure Application Gateway WAF v2 with FireWatch AI  
**Course:** INFT1204-01 Special Topics — Durham College  
**Team:** Galip Erdem, Thomas Barton-Hammond, David Stralak, Jeremy Hannah  
**Date:** March 2026

---

## 1. Test Objectives

The primary objectives of this testing plan are to:

1. **Validate WAF effectiveness** — Confirm that the Azure Application Gateway WAF v2 successfully blocks OWASP Top 10 attack vectors (SQL injection, cross-site scripting, local file inclusion) while allowing legitimate traffic to pass through unimpeded.

2. **Verify custom rule functionality** — Test all three custom WAF rules independently:
   - Geo-blocking restricts traffic to Canada and United States only
   - Rate limiting blocks IPs exceeding 100 requests per minute (excluding socket.io WebSocket traffic)
   - IP reputation blocking denies access from known Tor exit node IPs

3. **Demonstrate WAF operating modes** — Provide evidence that the WAF operates correctly in Detection mode (logs but allows), Prevention mode (actively blocks), and that legitimate traffic is allowed in both modes.

4. **Measure performance impact** — Verify that WAF-added latency remains below 200ms, ensuring the security layer does not degrade user experience.

5. **Validate monitoring integration** — Confirm that Azure Log Analytics receives firewall and access logs, KQL queries return structured data, and the monitoring dashboard displays real-time attack data.

6. **Verify AI-powered analysis** — Confirm that FireWatch AI successfully syncs logs from Azure, performs per-IP threat scoring, and generates actionable recommendations via LLM-based classification.

---

## 2. Scope of Testing

### In Scope

| Area | Description |
|------|-------------|
| SQL Injection (SQLi) | URL parameter injection, POST body injection, UNION-based injection |
| Cross-Site Scripting (XSS) | Reflected XSS in URL parameters, XSS in HTTP headers, encoded XSS payloads |
| Local File Inclusion (LFI) | Path traversal attempts targeting /etc/passwd and similar paths |
| Rate Limiting | Rapid request flooding to verify threshold enforcement at 100 req/min |
| Geo-Blocking | Verification that traffic from non-CA/US origins is blocked |
| IP Reputation | Verification that known Tor exit node IPs are denied access |
| Legitimate Traffic | Normal browsing, search, login, and API interactions pass without interference |
| WAF Mode Switching | Detection vs Prevention mode behavior comparison using identical payloads |
| Latency | Response time measurement through the WAF under normal load |
| Log Integrity | Verification that blocked events appear in Azure Log Analytics with correct fields |
| FireWatch AI | Azure log sync, threat scoring, AI classification, and dashboard functionality |

### Out of Scope

| Area | Rationale |
|------|-----------|
| Large-scale DDoS simulation | Azure student subscription cannot sustain volumetric load testing; rate limiting is tested at threshold level |
| Advanced persistent threats | Multi-stage attack chains are beyond the scope of a WAF-focused project |
| SSL/TLS testing | The project uses HTTP (port 80) for simplicity; HTTPS would require certificate management |
| Zero-day exploit testing | Managed rulesets protect against known patterns; unknown vulnerabilities are outside WAF scope |
| Physical security / social engineering | Not applicable to a cloud WAF deployment |

---

## 3. Test Cases

### 3.1 Managed Rule Tests

| Test ID | Description | Preconditions | Steps | Expected Result |
|---------|-------------|---------------|-------|-----------------|
| TC-01 | SQL Injection — basic OR payload | WAF in Prevention mode, Juice Shop accessible | Send: `curl "http://<IP>/rest/products/search?q=test' OR '1'='1"` | HTTP 403 Forbidden. WAF log shows rule 942xxx triggered with action "Blocked" |
| TC-02 | SQL Injection — UNION SELECT | WAF in Prevention mode | Send: `curl "http://<IP>/rest/products/search?q=test' UNION SELECT null,null--"` | HTTP 403 Forbidden. Log shows SQLi rule match |
| TC-03 | XSS — reflected in URL parameter | WAF in Prevention mode | Send: `curl "http://<IP>/rest/products/search?q=<script>alert('xss')</script>"` | HTTP 403 Forbidden. Log shows rule 941xxx triggered |
| TC-04 | XSS — in User-Agent header | WAF in Prevention mode | Send: `curl -H "User-Agent: <script>alert('xss')</script>" "http://<IP>/"` | HTTP 403 Forbidden. Log shows XSS rule match on header |
| TC-05 | XSS — URL-encoded payload | WAF in Prevention mode | Send: `curl "http://<IP>/rest/products/search?q=%3Cscript%3Ealert(1)%3C/script%3E"` | HTTP 403 Forbidden. WAF decodes and blocks |
| TC-06 | Local File Inclusion | WAF in Prevention mode | Send: `curl "http://<IP>/rest/products/search?q=../../../../etc/passwd"` | HTTP 403 Forbidden. Log shows rule 930xxx triggered |

### 3.2 Custom Rule Tests

| Test ID | Description | Preconditions | Steps | Expected Result |
|---------|-------------|---------------|-------|-----------------|
| TC-07 | Geo-blocking — blocked country | WAF in Prevention mode | Connect via VPN to a country outside CA/US (e.g., Germany, Brazil). Access `http://<IP>/` | HTTP 403 Forbidden. Log shows GeoBlockRule triggered |
| TC-08 | Geo-blocking — allowed country | WAF in Prevention mode | Access from Canadian IP (no VPN) | HTTP 200 OK. No GeoBlockRule log entry |
| TC-09 | Rate limiting — exceed threshold | WAF in Prevention mode | Run: `for i in $(seq 1 120); do curl -s -o /dev/null -w "%{http_code}\n" "http://<IP>/api/Challenges/"; done` | First ~100 requests return HTTP 200, subsequent requests return HTTP 403 |
| TC-10 | Rate limiting — socket.io excluded | WAF in Prevention mode | Browse Juice Shop normally for 2+ minutes (socket.io generates background polling) | No rate limit triggered. Normal browsing continues uninterrupted |
| TC-11 | IP reputation — Tor exit node | WAF in Prevention mode | Add test IP to the Tor exit node blocklist in Terraform. Access from that IP | HTTP 403 Forbidden. Log shows IPReputationBlock triggered |

### 3.3 Operational Tests

| Test ID | Description | Preconditions | Steps | Expected Result |
|---------|-------------|---------------|-------|-----------------|
| TC-12 | Detection mode — SQLi logged but allowed | WAF in Detection mode | Send SQLi payload from TC-01 | HTTP 200 OK (not blocked). WAF log shows rule with action "Detected" |
| TC-13 | Prevention mode — SQLi blocked | WAF in Prevention mode | Send same SQLi payload from TC-01 | HTTP 403 Forbidden. WAF log shows action "Blocked" |
| TC-14 | Legitimate traffic — homepage | WAF in Prevention mode | Access `http://<IP>/` in browser | HTTP 200 OK. Juice Shop loads normally |
| TC-15 | Legitimate traffic — search | WAF in Prevention mode | Access `http://<IP>/rest/products/search?q=apple` | HTTP 200 OK. Search results returned |
| TC-16 | Legitimate traffic — API | WAF in Prevention mode | Access `http://<IP>/api/Challenges/` | HTTP 200 OK. JSON response returned |
| TC-17 | Load balancing verification | Both VMs healthy, WAF in any mode | Send 10 requests via curl. Check Docker logs on both VMs | Both VMs show incoming requests in Docker logs |

### 3.4 Performance Tests

| Test ID | Description | Preconditions | Steps | Expected Result |
|---------|-------------|---------------|-------|-----------------|
| TC-18 | Latency measurement | WAF in Prevention mode | Run: `for i in $(seq 1 20); do curl -s -o /dev/null -w "%{time_total}\n" "http://<IP>/"; done` | Average response time < 200ms. No requests exceed 500ms |

### 3.5 Monitoring & AI Tests

| Test ID | Description | Preconditions | Steps | Expected Result |
|---------|-------------|---------------|-------|-----------------|
| TC-19 | Log Analytics ingestion | Diagnostic settings enabled | Generate attack traffic, wait 5-10 min, run KQL query in Log Analytics | Firewall logs appear with correct fields: TimeGenerated, clientIp_s, ruleId_s, action_s, requestUri_s |
| TC-20 | KQL dashboard | Log Analytics receiving data | Open Azure Dashboard with pinned KQL tiles | Dashboard displays: blocked attacks over time, top rules, attack types, top IPs |
| TC-21 | FireWatch AI — sync | FireWatch running, Azure CLI authenticated | Settings → enter Workspace ID → click "Sync now" | Toast notification confirms sync. Dashboard tab populates with attack data |
| TC-22 | FireWatch AI — analysis | Logs synced, Ollama running | AI Analysis tab → click "Generate summary" | AI classifies each IP, produces threat scores (0-100), generates BLOCK/INVESTIGATE/MONITOR recommendations |
| TC-23 | FireWatch AI — drill-down | AI analysis complete | Click an IP address in threat actors table | Modal shows: event count, block rate, attack types, AI assessment, recent logs |

---

## 4. Test Environment

### Infrastructure

| Component | Specification |
|-----------|--------------|
| Cloud Platform | Microsoft Azure (Student Subscription, Canada Central region) |
| Application Gateway | WAF_v2 SKU with autoscale (min 1, max 2 instances) |
| Backend VMs | 2x Standard_B1s (Ubuntu 22.04 LTS) in Availability Zones 2 and 3 |
| Web Application | OWASP Juice Shop v16 running in Docker containers on port 3000 |
| WAF Policy | OWASP CRS 3.2 managed ruleset + Microsoft Bot Manager + 3 custom rules |
| Monitoring | Azure Log Analytics Workspace (law-waf-project) |
| IaC | Terraform (full infrastructure defined in HCL, deployed via `terraform apply`) |

### FireWatch AI Environment

| Component | Specification |
|-----------|--------------|
| Runtime | Python 3.13 / FastAPI / uvicorn |
| Database | SQLite (firewatch.db) |
| AI Model | Ollama running qwen2.5:14b locally |
| Host | WSL2 Ubuntu (development) or Windows (presentation) |
| Azure SDK | azure-identity + azure-monitor-query (DefaultAzureCredential via Azure CLI) |

### Testing Tools

| Tool | Purpose |
|------|---------|
| curl | Manual HTTP request crafting for targeted attack payloads |
| OWASP ZAP | Automated vulnerability scanning for before/after WAF comparison |
| Bash scripts | Automated test suites (run-tests.sh, test-ip-reputation.sh) |
| Azure Portal | KQL query execution and dashboard verification |
| Browser (Chrome) | Legitimate traffic testing and FireWatch AI dashboard interaction |
| ProtonVPN | Geo-blocking test from non-CA/US IP addresses |

### Network Configuration

```
VNet: 10.0.0.0/16
├── subnet-appgw:    10.0.0.0/24  (Application Gateway)
├── subnet-backend:  10.0.1.0/24  (VM-Web-01: 10.0.1.4, VM-Web-02: 10.0.1.5)
└── Log Analytics Workspace: law-waf-project

NSG (nsg-backend):
  ALLOW: 10.0.0.0/24 → port 3000 (AppGW to backend)
  ALLOW: Admin IP → port 22 (SSH management)
  DENY:  All other inbound traffic
```

---

## 5. Roles and Responsibilities

| Role | Team Member | Responsibilities |
|------|-------------|-----------------|
| Project Lead & AI Developer | Galip Erdem | Architecture design, Terraform IaC, FireWatch AI development, Azure configuration, testing coordination |
| Infrastructure & Deployment | Thomas Barton-Hammond | Terraform deployment execution, Azure Portal verification, backend health monitoring |
| Security Tester | Jeremy Hannah | Attack payload execution (SQLi, XSS, LFI), OWASP ZAP scanning, rate limit testing |
| Documentation & QA | David Stralak | Screenshot collection, test result documentation, report compilation, presentation preparation |

All team members participate in the live demonstration and can explain any component of the system.

---


### Resources

| Resource | Details | Cost |
|----------|---------|------|
| Azure Student Credits | $100 allocation for all infrastructure | ~$2-3 per work session (terraform destroy between sessions) |
| Terraform | Open source IaC tool | Free |
| OWASP ZAP | Open source vulnerability scanner | Free |
| Ollama + qwen2.5:14b | Local LLM for AI classification | Free (runs on local hardware — NVIDIA RTX 4090) |
| ProtonVPN | Free tier for geo-blocking tests | Free |
| GitHub | Private repository for version control | Free |

### Cost Management Strategy

Infrastructure is deployed via `terraform apply` at the start of each work session and destroyed via `terraform destroy` at the end. The WAF_v2 SKU (~$0.36/hr) is the primary cost driver. Estimated total project cost: $15-20 of $100 available credit.

---

*Document version: 1.0 — March 2026*
