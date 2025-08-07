#!/bin/bash

# GPU Pilot Setup Script
# This script helps you set up the GPU auto-scaling system

set -e

echo "🚀 GPU Pilot Setup Script"
echo "=========================="

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo "⚠️  This script should not be run as root"
   exit 1
fi

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo "📋 Checking prerequisites..."

if ! command_exists terraform; then
    echo "❌ Terraform not found. Please install Terraform first."
    echo "   Visit: https://developer.hashicorp.com/terraform/downloads"
    exit 1
fi

if ! command_exists aws; then
    echo "❌ AWS CLI not found. Please install AWS CLI first."
    echo "   Visit: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi

if ! command_exists python3; then
    echo "❌ Python 3 not found. Please install Python 3 first."
    exit 1
fi

echo "✅ Prerequisites check passed"

# Get current directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR"

# Initialize Terraform
echo "🔧 Initializing Terraform..."
cd "$PROJECT_ROOT/terraform-scale"

if [ ! -d ".terraform" ]; then
    terraform init
    echo "✅ Terraform initialized"
else
    echo "✅ Terraform already initialized"
fi

# Create terraform.tfvars if it doesn't exist
if [ ! -f "terraform.tfvars" ]; then
    echo "📝 Creating terraform.tfvars template..."
    cat > terraform.tfvars << EOF
# AWS Configuration
region = "us-west-2"

# VPC and Network Configuration
# vpc_id = "vpc-xxxxxxxxx"  # Leave empty to use default VPC
# subnet_ids = ["subnet-xxxxxxxxx", "subnet-yyyyyyyyy"]  # Leave empty to use default subnets

# Instance Configuration
ami_id = "ami-0c02fb55956c7d316"  # Replace with your custom AMI with CUDA and Slurm
instance_type = "g4dn.xlarge"
# key_name = "your-key-pair"  # Uncomment and set your EC2 key pair

# Scaling Configuration
min_size = 0
max_size = 10
desired_capacity_up = 2

# Security (if you have existing security groups)
# security_group_ids = ["sg-xxxxxxxxx"]
EOF
    echo "✅ Created terraform.tfvars template"
    echo "⚠️  Please edit terraform.tfvars with your actual values before proceeding"
fi

# Setup Python environment
echo "🐍 Setting up Python environment..."
cd "$PROJECT_ROOT/scaler"

if [ ! -d "venv" ]; then
    python3 -m venv venv
    echo "✅ Created Python virtual environment"
fi

source venv/bin/activate
pip install -r requirements.txt
echo "✅ Installed Python dependencies"

# Create systemd service file
echo "🔧 Creating systemd service..."
sudo tee /etc/systemd/system/gpu-scaler.service > /dev/null << EOF
[Unit]
Description=GPU Auto-Scaler Service
After=network.target

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_ROOT/scaler
Environment=PATH=$PROJECT_ROOT/scaler/venv/bin
Environment=SCALER_SECRET_TOKEN=your-secret-token-here
ExecStart=$PROJECT_ROOT/scaler/venv/bin/python scaler.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
echo "✅ Created systemd service"

# Create log directory
sudo mkdir -p /var/log
sudo touch /var/log/gpu-scaler.log
sudo chown $USER:$USER /var/log/gpu-scaler.log

echo ""
echo "🎉 Setup completed!"
echo ""
echo "Next steps:"
echo "1. Configure AWS credentials: aws configure"
echo "2. Edit terraform-scale/terraform.tfvars with your AWS settings"
echo "3. Create and configure your custom AMI with CUDA and Slurm"
echo "4. Set environment variable: export SCALER_SECRET_TOKEN=your-secret-token"
echo "5. Test terraform: cd terraform-scale && terraform plan"
echo "6. Start the scaler service: sudo systemctl enable gpu-scaler && sudo systemctl start gpu-scaler"
echo "7. Configure Prometheus and Alertmanager using files in monitoring/"
echo ""
echo "📚 Check README.md for detailed instructions"
