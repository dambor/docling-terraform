terraform {
  required_version = ">= 1.0"
  required_providers {
    ibm = {
      source  = "IBM-Cloud/ibm"
      version = "~> 1.63"
    }
  }
}

# Variables
variable "ibmcloud_api_key" {
  description = "IBM Cloud API Key"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "IBM Cloud region"
  type        = string
  default     = "us-south"
}

variable "zone" {
  description = "IBM Cloud availability zone (e.g., us-south-1, us-south-2, us-south-3)"
  type        = string
  default     = ""
}

variable "zone_index" {
  description = "Index of zone to use (1, 2, or 3)"
  type        = number
  default     = 1
}

locals {
  # Use provided zone or construct from region and index
  zone = var.zone != "" ? var.zone : "${var.region}-${var.zone_index}"
}

variable "resource_group" {
  description = "Resource group name"
  type        = string
  default     = "default"
}

variable "ssh_key_name" {
  description = "Name for the SSH key"
  type        = string
  default     = "docling-ssh-key"
}

variable "ssh_public_key" {
  description = "SSH public key content"
  type        = string
}

# Provider configuration
provider "ibm" {
  ibmcloud_api_key = var.ibmcloud_api_key
  region           = var.region
}

# Data sources
data "ibm_resource_group" "group" {
  name = var.resource_group
}

# Get available zones for the region
data "ibm_is_zones" "regional_zones" {
  region = var.region
}

data "ibm_is_image" "ubuntu" {
  name = "ibm-ubuntu-22-04-4-minimal-amd64-1"
}

# VPC
resource "ibm_is_vpc" "docling_vpc" {
  name           = "docling-vpc"
  resource_group = data.ibm_resource_group.group.id
}

# Subnet
resource "ibm_is_subnet" "docling_subnet" {
  name                     = "docling-subnet"
  vpc                      = ibm_is_vpc.docling_vpc.id
  zone                     = local.zone
  total_ipv4_address_count = 256
  resource_group           = data.ibm_resource_group.group.id
}

# Security Group
resource "ibm_is_security_group" "docling_sg" {
  name           = "docling-security-group"
  vpc            = ibm_is_vpc.docling_vpc.id
  resource_group = data.ibm_resource_group.group.id
}

# Security Group Rules
resource "ibm_is_security_group_rule" "docling_ssh" {
  group     = ibm_is_security_group.docling_sg.id
  direction = "inbound"
  remote    = "0.0.0.0/0"
  protocol  = "tcp"
  port_min  = 22
  port_max  = 22
}

resource "ibm_is_security_group_rule" "docling_http" {
  group     = ibm_is_security_group.docling_sg.id
  direction = "inbound"
  remote    = "0.0.0.0/0"
  protocol  = "tcp"
  port_min  = 5001
  port_max  = 5001
}

resource "ibm_is_security_group_rule" "docling_https" {
  group     = ibm_is_security_group.docling_sg.id
  direction = "inbound"
  remote    = "0.0.0.0/0"
  protocol  = "tcp"
  port_min  = 443
  port_max  = 443
}

resource "ibm_is_security_group_rule" "docling_http_alt" {
  group     = ibm_is_security_group.docling_sg.id
  direction = "inbound"
  remote    = "0.0.0.0/0"
  protocol  = "tcp"
  port_min  = 80
  port_max  = 80
}

resource "ibm_is_security_group_rule" "docling_outbound" {
  group     = ibm_is_security_group.docling_sg.id
  direction = "outbound"
  remote    = "0.0.0.0/0"
}

# SSH Key
resource "ibm_is_ssh_key" "docling_key" {
  name           = var.ssh_key_name
  public_key     = var.ssh_public_key
  resource_group = data.ibm_resource_group.group.id
}

# Public Gateway for internet access
resource "ibm_is_public_gateway" "docling_gateway" {
  name           = "docling-gateway"
  vpc            = ibm_is_vpc.docling_vpc.id
  zone           = local.zone
  resource_group = data.ibm_resource_group.group.id
}

resource "ibm_is_subnet_public_gateway_attachment" "docling_gateway_attachment" {
  subnet         = ibm_is_subnet.docling_subnet.id
  public_gateway = ibm_is_public_gateway.docling_gateway.id
}

# Floating IP
resource "ibm_is_floating_ip" "docling_fip" {
  name           = "docling-floating-ip"
  target         = ibm_is_instance.docling_vm.primary_network_interface[0].id
  resource_group = data.ibm_resource_group.group.id
}

# Virtual Server Instance
resource "ibm_is_instance" "docling_vm" {
  name           = "docling-server"
  image          = data.ibm_is_image.ubuntu.id
  profile        = "bx2-2x8"
  resource_group = data.ibm_resource_group.group.id

  primary_network_interface {
    subnet          = ibm_is_subnet.docling_subnet.id
    security_groups = [ibm_is_security_group.docling_sg.id]
  }

  vpc  = ibm_is_vpc.docling_vpc.id
  zone = local.zone
  keys = [ibm_is_ssh_key.docling_key.id]

  user_data = <<-EOF
              #!/bin/bash
              set -e
              
              # Update system
              apt-get update
              apt-get upgrade -y
              
              # Install dependencies
              apt-get install -y python3-pip python3-venv git curl libgl1 libglib2.0-0
              
              # Create app user
              useradd -m -s /bin/bash docling
              
              # Setup Docling serve
              su - docling << 'USEREOF'
              # Create virtual environment
              python3 -m venv ~/docling-env
              source ~/docling-env/bin/activate
              
              # Install docling-serve with UI support
              pip install --upgrade pip
              pip install "docling-serve[ui]"
              
              USEREOF
              
              # Create systemd service
              cat > /etc/systemd/system/docling.service << 'SERVICEEOF'
              [Unit]
              Description=Docling Serve
              After=network.target
              
              [Service]
              Type=simple
              User=docling
              WorkingDirectory=/home/docling
              Environment="PATH=/home/docling/docling-env/bin"
              Environment="DOCLING_SERVE_HOST=0.0.0.0"
              Environment="DOCLING_SERVE_PORT=5001"
              Environment="DOCLING_SERVE_ENABLE_UI=1"
              ExecStart=/home/docling/docling-env/bin/docling-serve run
              Restart=always
              RestartSec=10
              
              [Install]
              WantedBy=multi-user.target
              SERVICEEOF
              
              # Enable and start service
              systemctl daemon-reload
              systemctl enable docling.service
              systemctl start docling.service
              
              echo "Docling serve installation completed!"
              EOF

  tags = ["docling", "terraform"]
}

# Outputs
output "vm_id" {
  description = "ID of the virtual server instance"
  value       = ibm_is_instance.docling_vm.id
}

output "public_ip" {
  description = "Public IP address of the VM"
  value       = ibm_is_floating_ip.docling_fip.address
}

output "docling_url" {
  description = "URL to access Docling serve"
  value       = "http://${ibm_is_floating_ip.docling_fip.address}:5001"
}

output "docling_ui_url" {
  description = "URL to access Docling UI playground"
  value       = "http://${ibm_is_floating_ip.docling_fip.address}:5001/ui"
}

output "docling_api_docs" {
  description = "URL to access Docling API documentation"
  value       = "http://${ibm_is_floating_ip.docling_fip.address}:5001/docs"
}

output "access_instructions" {
  description = "How to access Docling serve publicly"
  value       = <<-EOT
  
  Docling is now publicly accessible at:
  - API: http://${ibm_is_floating_ip.docling_fip.address}:5001
  - API Docs: http://${ibm_is_floating_ip.docling_fip.address}:5001/docs
  - UI Playground: http://${ibm_is_floating_ip.docling_fip.address}:5001/ui
  
  Test with: curl http://${ibm_is_floating_ip.docling_fip.address}:5001/v1/convert/source -X POST -H "Content-Type: application/json" -d '{"sources": [{"kind": "http", "url": "https://arxiv.org/pdf/2501.17887"}]}'
  EOT
}

output "ssh_command" {
  description = "SSH command to connect to the VM"
  value       = "ssh -i <your-private-key> root@${ibm_is_floating_ip.docling_fip.address}"
}
