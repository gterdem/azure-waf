# Azure Cloud-Based Web Application Firewall (WAF) Project

A hands-on cloud cybersecurity project, deploying an Azure Application Gateway with WAF v2 to protect a vulnerable web application (OWASP Juice Shop). It will also have attack vectors and network monitoring.

## What This Project Does

This project deploys a complete WAF environment on Azure using Terraform:

- **2 web servers** running OWASP Juice Shop (a deliberately vulnerable app) behind a load balancer
- **Azure Application Gateway with WAF v2** inspecting all traffic before it reaches the servers
- **Managed rules** (OWASP CRS 3.2) blocking SQL injection, XSS, and other OWASP Top 10 attacks
- **Custom rules** for geo-blocking, rate limiting, and IP reputation blocking
- **Azure Monitor + Log Analytics** for logging, dashboards, and alerting
- **FireWatch AI application** (Python) a custom application for intelligent threat analysis beyond what rules catch

## Architecture

![Architecture Diagram](diagrams/azure_WAF_architecture_diagram.png)


## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| [Terraform](https://developer.hashicorp.com/terraform/install) | >= 1.5 | Infrastructure deployment |
| [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux) | >= 2.50 | Azure authentication |
| [Git](https://git-scm.com/) | any | Version control |
| Azure for Students subscription | $100 credit | Cloud resources |

## Quick Start

### 1. Clone and configure
```bash
git clone https://github.com/gterdem/azure-waf.git
cd azure-waf/terraform
```

### 2. One-time Azure setup
```bash
# Login to Azure
az login

# Register required resource providers (one-time per subscription)
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.Compute
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.Insights

# Verify registration (wait until all show "Registered")
az provider show -n Microsoft.Network --query "registrationState" -o tsv
```

### 3. Create your variables file
#### Linux:
```bash 
cat > terraform.tfvars << 'EOF'
subscription_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
allowed_ssh_ip  = "0.0.0.0"
EOF
```
#### Windows:
Create a new file with the following lines and save it as **terraform.tfvars**:
```bash
subscription_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
allowed_ssh_ip  = "0.0.0.0"
```

Edit `terraform.tfvars` with your values:
```hcl
subscription_id = "your-azure-subscription-id" # az account show --query id -o tsv
allowed_ssh_ip  = "your-public-ip"             # curl -s ifconfig.me
```

### 4. Deploy
```bash
terraform init    # Download providers (first time only)
terraform plan    # Preview what will be created
terraform apply   # Deploy everything (confirm with "yes")
```

### 5. Destroy (IMPORTANT — to save credit)
Whenever you are done working on the project, destroy the infrastructure. I don't think there is a way to stop the gateway and it is the most expensive component. I might update this sectin later.

```bash
terraform destroy   # Tears down everything (confirm with "yes")
```

> **Cost warning:** The WAF v2 SKU charges ~$0.36/hr. Always `terraform destroy` when you're not actively working. Re-deploy anytime with `terraform apply`.

## Project Structure
```
azure-waf-project/
├── terraform/              # All infrastructure as code
├── firewatch/              # AI-powered threat analysis module
├── testing/                # Attack scripts and evidence
├── diagrams/               # Architecture diagrams
└── README.md               # You are here
```

## Cost Estimate

| Resource | Hourly Cost | Notes |
|----------|-------------|-------|
| Application Gateway WAF_v2 | ~$0.36/hr | Most expensive — destroy when idle |
| 2x Standard_B1s VMs | ~$0.02/hr total | Very cheap |
| Public IP (Standard) | ~$0.005/hr | Minimal |
| Log Analytics | Per GB ingested | Negligible  |
| **Total per session** | **~$2-3 for 4hrs** | Seems reasonable for $100 credit |

## License

Educational project — feel free to use as a learning reference.
