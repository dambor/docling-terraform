# Docling Serve on IBM Cloud

Deploy [Docling Serve](https://github.com/docling-project/docling-serve) on IBM Cloud using Terraform. This creates a VM with Docling running as an API service with UI playground.

## Prerequisites

- IBM Cloud account
- IBM Cloud CLI installed ([Installation guide](https://cloud.ibm.com/docs/cli?topic=cli-getting-started))
- Terraform installed ([Download](https://www.terraform.io/downloads))
- SSH key pair (or generate a new one)

## Setup Instructions

### 1. Install IBM Cloud CLI and Login

```bash
# Install IBM Cloud CLI (if not already installed)
# macOS
brew install ibmcloud-cli

# Linux
curl -fsSL https://clis.cloud.ibm.com/install/linux | sh

# Login to IBM Cloud
ibmcloud login --sso  # Use SSO if your account requires it
# OR
ibmcloud login  # Username/password login
```

### 2. Install Required Plugins

```bash
# Install the VPC infrastructure plugin
ibmcloud plugin install vpc-infrastructure

# Verify installation
ibmcloud plugin list
```

### 3. Gather Required Information

#### Get IBM Cloud API Key

```bash
# Create a new API key
ibmcloud iam api-key-create docling-terraform-key -d "API key for Docling Terraform deployment"

# IMPORTANT: Save the API key that's displayed - you won't be able to see it again!
```

#### Get or Generate SSH Key

```bash
# Option 1: Use existing SSH key
cat ~/.ssh/id_rsa.pub

# Option 2: Generate a new SSH key
ssh-keygen -t rsa -b 4096 -f ~/.ssh/docling_key -N ""
cat ~/.ssh/docling_key.pub
```

#### List Available Regions

```bash
# View all available regions
ibmcloud regions

# Common regions:
# - us-south (Dallas)
# - us-east (Washington DC)
# - ca-tor (Toronto)
# - eu-de (Frankfurt)
# - eu-gb (London)
# - jp-tok (Tokyo)
```

#### List Resource Groups

```bash
# List your resource groups
ibmcloud resource groups

# Most accounts have a "default" resource group
```

### 4. Create Terraform Configuration

Clone this repository:

```bash
git clone https://github.com/dambor/docling-terraform.git
cd docling-terraform
```

### 5. Create `terraform.tfvars`

Create a file named `terraform.tfvars` with your configuration:

```hcl
# IBM Cloud API Key (from step 3)
ibmcloud_api_key = "your-api-key-here"

# SSH Public Key (entire content from ~/.ssh/docling_key.pub or ~/.ssh/id_rsa.pub)
ssh_public_key   = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC... your-full-key-here"

# Region (choose from available regions)
region           = "ca-tor"

# Resource Group (usually "default")
resource_group   = "default"

# Optional: Specify zone explicitly (otherwise auto-generated from region)
# zone           = "ca-tor-1"

# Optional: Or use zone index (1, 2, or 3)
# zone_index     = 1
```

**IMPORTANT**: Never commit `terraform.tfvars` to version control. Add it to `.gitignore`:

```bash
echo "terraform.tfvars" >> .gitignore
echo "*.tfstate*" >> .gitignore
echo ".terraform/" >> .gitignore
```

### 6. Deploy Docling Serve

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

Type `yes` when prompted to confirm the deployment.

**Note**: The deployment takes approximately 10-15 minutes:
- Infrastructure creation: ~2-3 minutes
- System updates and package installation: ~3-5 minutes  
- Docling installation (pip packages and ML models): ~5-10 minutes

### 7. Access Docling Serve

After successful deployment, Terraform will output the access URLs:

```
Outputs:

access_instructions = <<EOT

Docling is now publicly accessible at:
- API: http://X.X.X.X:5001
- API Docs: http://X.X.X.X:5001/docs
- UI Playground: http://X.X.X.X:5001/ui

Test with: curl http://X.X.X.X:5001/v1/convert/source -X POST ...
EOT

docling_api_docs = "http://X.X.X.X:5001/docs"
docling_ui_url = "http://X.X.X.X:5001/ui"
docling_url = "http://X.X.X.X:5001"
public_ip = "X.X.X.X"
ssh_command = "ssh -i <your-private-key> root@X.X.X.X"
```

Open your browser to:
- **UI Playground**: `http://<public-ip>:5001/ui`
- **API Documentation**: `http://<public-ip>:5001/docs`

### 8. Test the API

```bash
# Simple health check
curl http://<public-ip>:5001/docs

# Test document conversion
curl http://<public-ip>:5001/v1/convert/source \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "sources": [{"kind": "http", "url": "https://arxiv.org/pdf/2501.17887"}]
  }'
```

## Troubleshooting

### Check Service Status

```bash
# SSH into the VM
ssh -i ~/.ssh/docling_key root@<public-ip>

# Check if service is running
systemctl status docling

# View service logs
journalctl -u docling -n 100 --no-pager

# Check if it's listening on port 5001
ss -tlnp | grep 5001

# Monitor cloud-init progress (during initial deployment)
cloud-init status
tail -f /var/log/cloud-init-output.log
```

### Common Issues

**Service not accessible externally but works locally:**
- Security group rules may not be applied correctly
- Run `terraform apply` again to ensure all rules are created

**Service fails to start:**
- Check logs: `journalctl -u docling -n 50 --no-pager`
- Most common issue: Missing system libraries (should be fixed in the Terraform)

**Installation taking too long:**
- Normal! The pip installation downloads several GB of ML models
- Wait 10-15 minutes for full deployment

## Managing the Deployment

### View Current State

```bash
# Show all deployed resources
terraform show

# List all resources
terraform state list

# Show specific resource details
terraform state show ibm_is_instance.docling_vm
```

### Update Configuration

```bash
# After modifying main.tf or terraform.tfvars
terraform plan    # Preview changes
terraform apply   # Apply changes
```

### Destroy Infrastructure

```bash
# WARNING: This will delete all resources
terraform destroy
```

Type `yes` when prompted to confirm destruction.

## Cost Estimation

The default configuration uses:
- **VM Profile**: bx2-2x8 (2 vCPUs, 8GB RAM)
- **Storage**: Standard boot volume (100GB)
- **Network**: 1 Floating IP, 1 Public Gateway

Estimated monthly cost: ~$60-80 USD (varies by region)

To reduce costs, you can modify the VM profile in `main.tf`:
- `bx2-2x8`: 2 vCPUs, 8GB RAM (default)
- `bx2-4x16`: 4 vCPUs, 16GB RAM (for heavier workloads)
- `cx2-2x4`: 2 vCPUs, 4GB RAM (minimum for Docling)

## Security Notes

1. **Never commit sensitive files**:
   - `terraform.tfvars` (contains API keys)
   - `*.tfstate` files (contain resource details)
   - `.terraform/` directory

2. **API Key Security**:
   - Rotate API keys regularly
   - Use separate API keys for different environments
   - Revoke unused keys: `ibmcloud iam api-key-delete <key-name>`

3. **Network Security**:
   - The default configuration allows public access to port 5001
   - To restrict access, modify security group rules in `main.tf`
   - Consider adding IP whitelisting for production deployments

4. **SSH Access**:
   - Keep your private SSH key secure
   - Use `ssh-keygen` with a passphrase for additional security
   - Consider disabling password authentication (SSH key only)

## Advanced Configuration

### Use a Different VM Size

Edit `main.tf` and modify the `profile` line:

```hcl
resource "ibm_is_instance" "docling_vm" {
  # ...
  profile        = "bx2-4x16"  # Change this
  # ...
}
```

### Use a Different Region/Zone

Update your `terraform.tfvars`:

```hcl
region     = "us-south"
zone_index = 2  # Will create "us-south-2"
# OR
zone       = "us-south-2"  # Explicit zone
```

### Customize Docling Configuration

Edit the `user_data` section in `main.tf` to add environment variables:

```hcl
Environment="DOCLING_SERVE_HOST=0.0.0.0"
Environment="DOCLING_SERVE_PORT=5001"
Environment="DOCLING_SERVE_ENABLE_UI=1"
Environment="DOCLING_SERVE_LOG_LEVEL=INFO"  # Add custom config
```

## Additional Resources

- [Docling Documentation](https://github.com/docling-project/docling)
- [Docling Serve Documentation](https://github.com/docling-project/docling-serve)
- [IBM Cloud VPC Documentation](https://cloud.ibm.com/docs/vpc)
- [Terraform IBM Provider Docs](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs)

## Support

For issues with:
- **Docling**: [GitHub Issues](https://github.com/docling-project/docling-serve/issues)
- **IBM Cloud**: [Support Center](https://cloud.ibm.com/unifiedsupport/supportcenter)
- **Terraform**: Check deployment logs and Terraform state

## License

This Terraform configuration is provided as-is. Docling is licensed under MIT License.