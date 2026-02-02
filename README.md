# GPU Pilot - Automated GPU Scaling for HPC Clusters

GPU Pilot is an automated scaling solution that dynamically provisions GPU compute nodes based on Slurm workload demand. It uses Terraform for infrastructure management, Prometheus for monitoring, and AWS Auto Scaling Groups for elastic capacity.

## Architecture

```
Slurm Queue → Prometheus → Alertmanager → GPU Scaler Service → Terraform → AWS Auto Scaling Group
```

### Components

1. **Slurm Cluster** - HPC job scheduler with Prometheus exporter
2. **Prometheus** - Monitors Slurm metrics and evaluates alerting rules
3. **Alertmanager** - Sends webhooks to the scaler service
4. **GPU Scaler Service** - Flask REST API that triggers Terraform operations
5. **Terraform** - Manages AWS Auto Scaling Groups
6. **AWS GPU Nodes** - Elastic GPU compute instances

## Prerequisites

- AWS Account with EC2, Auto Scaling, and VPC permissions
- AWS CLI configured
- Terraform >= 1.0
- Python 3.7+
- Slurm cluster with Prometheus exporter
- Prometheus and Alertmanager

## Installation

### Install Required Dependencies

**System packages:**
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y python3 python3-pip python3-venv

# Install Terraform
sudo snap install terraform
# Or download from: https://www.terraform.io/downloads

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

**Python dependencies:**
```bash
cd gpu_pilot/scaler
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

Or use the automated setup script that installs everything:
```bash
./setup.sh
```

## Quick Start

### 1. Setup

```bash
git clone <repository-url>
cd gpu_pilot
chmod +x setup.sh
./setup.sh
```

### 2. Configure AWS Resources

Edit `terraform-scale/terraform.tfvars`:

```hcl
region = "us-west-2"
vpc_id = ""  # Leave empty for default VPC
subnet_ids = []  # Leave empty for default subnets

ami_id = "ami-0123456789abcdef"  # Your custom AMI with CUDA + Slurm
instance_type = "g4dn.xlarge"
key_name = "your-keypair-name"

min_size = 0
max_size = 10
desired_capacity_up = 2
```

### 3. Initialize Terraform

```bash
cd terraform-scale
terraform init
terraform validate
terraform plan
terraform apply -var="scale_up=false"
```

### 4. Configure Authentication

```bash
export SCALER_SECRET_TOKEN=$(openssl rand -hex 32)
sudo nano /etc/systemd/system/gpu-scaler.service
# Update Environment="SCALER_SECRET_TOKEN=..." with your token
sudo systemctl daemon-reload
```

### 5. Start Service

```bash
sudo systemctl enable gpu-scaler
sudo systemctl start gpu-scaler
sudo systemctl status gpu-scaler
curl http://localhost:5000/health
```

### 6. Configure Prometheus and Alertmanager

Copy `monitoring/prometheus-rules.yml` to your Prometheus rules directory.

Update `alertmanager.yml`:

```yaml
receivers:
  - name: 'gpu-scaler-up'
    webhook_configs:
      - url: "http://your-scaler-host:5000/scale"
        send_resolved: false
        http_config:
          bearer_token: "your-secret-token-here"

  - name: 'gpu-scaler-down'
    webhook_configs:
      - url: "http://your-scaler-host:5000/scale"
        send_resolved: true
        http_config:
          bearer_token: "your-secret-token-here"
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `SCALER_SECRET_TOKEN` | Bearer token for API authentication | `your-secret-token-here` |
| `TERRAFORM_DIR` | Path to Terraform configuration | `../terraform-scale` |
| `COOLDOWN_PERIOD` | Seconds between scale operations | `300` |

### Terraform Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `scale_up` | Scale up (true) or down (false) | `false` |
| `region` | AWS region | `us-west-2` |
| `vpc_id` | VPC ID (empty for default) | `""` |
| `subnet_ids` | Subnet IDs (empty for default) | `[]` |
| `ami_id` | AMI with CUDA and Slurm | Required |
| `instance_type` | EC2 instance type | `g4dn.xlarge` |
| `key_name` | EC2 key pair name | `""` |
| `security_group_ids` | Security group IDs | `[]` |
| `min_size` | Minimum instances | `0` |
| `max_size` | Maximum instances | `10` |
| `desired_capacity_up` | Desired capacity when scaling up | `2` |

## API Endpoints

### Health Check

```http
GET /health
```

Response:
```json
{
  "status": "healthy",
  "timestamp": "2026-02-02T10:30:00.000000",
  "terraform_dir": "/path/to/terraform-scale",
  "version": "1.0.0"
}
```

### Scale Operation

```http
POST /scale
Authorization: Bearer <token>
Content-Type: application/json

{
  "action": "scale_up"
}
```

Success (202):
```json
{
  "status": "accepted",
  "action": "scale_up",
  "message": "Scaling operation scale_up initiated",
  "timestamp": "2026-02-02T10:30:00.000000"
}
```

Cooldown Active (429):
```json
{
  "status": "rejected",
  "error": "Cooldown period active",
  "cooldown_remaining_seconds": 180
}
```

### Status Check

```http
GET /status
Authorization: Bearer <token>
```

Response:
```json
{
  "status": "success",
  "terraform_outputs": {
    "autoscaling_group_name": {"value": "hpc-gpu-asg"},
    "current_desired_capacity": {"value": 2}
  },
  "last_scale_times": {
    "scale_up": 1738492200.0
  },
  "terraform_dir": "/path/to/terraform-scale"
}
```

## Alerting Rules

Pre-configured alerts in `monitoring/prometheus-rules.yml`:

- **GPUNodesNeeded** - Triggers scale-up when GPU partition has >10 pending jobs for 1+ minute
- **LowGPUUtilization** - Triggers scale-down when no GPU jobs for 10+ minutes
- **TooManyPendingJobs** - General alert for >20 pending jobs
- **AutoScalerDown** - Critical alert when scaler service is down
- **HighAWSCosts** - Warning when costs exceed threshold

## Troubleshooting

### Service Issues

Check service status and logs:
```bash
sudo systemctl status gpu-scaler
sudo journalctl -u gpu-scaler -f
tail -f /var/log/gpu-scaler.log
```

### Terraform Issues

Verify credentials and initialization:
```bash
aws sts get-caller-identity
cd terraform-scale
terraform init
terraform validate
```

### Scaling Issues

Test manual scaling:
```bash
curl -X POST http://localhost:5000/scale \
  -H "Authorization: Bearer your-token" \
  -H "Content-Type: application/json" \
  -d '{"action":"scale_up"}'
```

Check AWS ASG:
```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names hpc-gpu-asg
```

## Security

- Use strong authentication tokens (generate with `openssl rand -hex 32`)
- Restrict security group access to necessary ports only
- Deploy scaler behind HTTPS proxy for production
- Use IAM roles with minimal required permissions
- Monitor logs for unauthorized access attempts

## Project Structure

```
gpu_pilot/
├── README.md                    # This file
├── setup.sh                     # Automated setup script
├── scaler/
│   ├── scaler.py               # Flask application
│   └── requirements.txt        # Python dependencies
├── terraform-scale/
│   ├── main.tf                 # Terraform configuration
│   ├── variables.tf            # Input variables
│   ├── outputs.tf              # Output values
│   └── user-data.sh            # Instance initialization script
└── monitoring/
    ├── prometheus-rules.yml    # Alert rules
    ├── prometheus.yml          # Example Prometheus config
    └── alertmanager.yml        # Example Alertmanager config
```

## License

This project is licensed under the MIT License.

## Important Notes

- This system provisions AWS resources that incur costs. Set up billing alerts.
- Never commit secrets or tokens to version control.
- Test in a non-production environment first.
- Monitor logs and AWS costs regularly.
