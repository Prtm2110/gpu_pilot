# GPU Pilot - Automated GPU Scaling for HPC Clusters

GPU Pilot is an automated scaling solution that dynamically provisions GPU compute nodes based on Slurm queue demand using Terraform, Prometheus, and AWS Auto Scaling Groups.

## 🏗️ Architecture

```
[Slurm Queue] → [Prometheus Alert] → [Python Scaler] → [Terraform] → [AWS GPU Nodes]
```

1. **Slurm** - Job scheduler with pending job metrics
2. **Prometheus** - Monitors Slurm metrics and triggers alerts
3. **Python Scaler** - Receives webhooks and executes Terraform
4. **Terraform** - Manages AWS Auto Scaling Groups
5. **AWS GPU Nodes** - Elastic compute nodes that auto-join the cluster

## 🚀 Quick Start

### 1. Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.0
- Python 3.7+
- Slurm cluster with prometheus exporter
- Prometheus and Alertmanager

### 2. Setup

```bash
# Clone and setup
git clone <your-repo>
cd gpu_pilot
./setup.sh
```

### 3. Configure AWS Settings

Edit `terraform-scale/terraform.tfvars`:

```hcl
# AWS Configuration
region = "us-west-2"
vpc_id = "vpc-12345678"  # Your VPC ID
subnet_ids = ["subnet-12345678", "subnet-87654321"]  # Your subnet IDs

# Instance Configuration
ami_id = "ami-12345678"  # Your custom AMI with CUDA + Slurm
instance_type = "g4dn.xlarge"
key_name = "my-key-pair"

# Scaling Configuration
max_size = 10
desired_capacity_up = 2
```

### 4. Initialize and Test Terraform

```bash
cd terraform-scale
terraform init
terraform plan
terraform apply -var="scale_up=false"  # Start with 0 instances
```

### 5. Start the Scaler Service

```bash
# Set your secret token
export SCALER_SECRET_TOKEN="your-super-secret-token"

# Start the service
sudo systemctl enable gpu-scaler
sudo systemctl start gpu-scaler

# Check status
sudo systemctl status gpu-scaler
curl -H "Authorization: Bearer your-super-secret-token" http://localhost:5000/health
```

### 6. Configure Monitoring

#### Prometheus Configuration

Add to your `prometheus.yml`:

```yaml
rule_files:
  - "path/to/gpu_pilot/monitoring/prometheus-rules.yml"

scrape_configs:
  - job_name: 'gpu-scaler'
    static_configs:
      - targets: ['localhost:5000']
    metrics_path: '/health'
```

#### Alertmanager Configuration

Update your `alertmanager.yml`:

```yaml
receivers:
- name: 'cloud-scaler-up'
  webhook_configs:
  - url: "http://your-scaler-host:5000/scale"
    send_resolved: false
    http_config:
      bearer_token: "your-super-secret-token"

- name: 'cloud-scaler-down'
  webhook_configs:
  - url: "http://your-scaler-host:5000/scale"
    send_resolved: true
    http_config:
      bearer_token: "your-super-secret-token"
```

## 🔧 Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `SCALER_SECRET_TOKEN` | Authentication token for webhooks | `your-secret-token-here` |

### Terraform Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `scale_up` | Whether to scale up (true) or down (false) | `false` |
| `region` | AWS region | `us-west-2` |
| `ami_id` | AMI ID for GPU instances | - |
| `instance_type` | EC2 instance type | `g4dn.xlarge` |
| `max_size` | Maximum instances in ASG | `10` |
| `desired_capacity_up` | Desired capacity when scaling up | `2` |

## 📡 API Endpoints

### Health Check
```bash
GET /health
```

### Scale Operations
```bash
POST /scale
Authorization: Bearer <token>
Content-Type: application/json

{
  "action": "scale_up"  # or "scale_down"
}
```

### Status Check
```bash
GET /status
Authorization: Bearer <token>
```

## 🔨 Creating Custom AMI

Your AMI should include:

1. **NVIDIA Drivers and CUDA**
2. **Slurm Worker Daemon**
3. **Munge Authentication**
4. **Prometheus Node Exporter**

### Sample AMI Build Script

```bash
#!/bin/bash
# Start with Amazon Linux 2 or Ubuntu 20.04

# Install NVIDIA drivers
yum install -y kernel-devel-$(uname -r) kernel-headers-$(uname -r)
wget https://developer.download.nvidia.com/compute/cuda/11.8.0/local_installers/cuda-repo-rhel7-11-8-local-11.8.0_520.61.05-1.x86_64.rpm
rpm -i cuda-repo-rhel7-11-8-local-11.8.0_520.61.05-1.x86_64.rpm
yum clean all
yum install -y cuda-toolkit-11-8

# Install Slurm
yum install -y epel-release
yum install -y slurm slurm-munge

# Configure auto-startup
systemctl enable slurmd
systemctl enable munge

# Install monitoring
yum install -y prometheus-node-exporter
systemctl enable prometheus-node-exporter
```

## 🚨 Alerting Rules

The system includes several pre-configured alerts:

- **TooManyPendingJobs** - Triggers scale-up when >20 jobs pending for 2 minutes
- **GPUNodesNeeded** - Triggers scale-up for GPU partition specifically
- **LowGPUUtilization** - Triggers scale-down when no GPU jobs for 10 minutes
- **AutoScalerDown** - Critical alert when scaler service is unavailable

## 🔒 Security

### Authentication
- Bearer token authentication for all API calls
- Configurable secret token via environment variable

### Network Security
- Auto-created security groups for GPU nodes
- Restricted access to Slurm ports (6817, 6818, 6809)
- SSH access limited to private networks

### Best Practices
- Run scaler service behind reverse proxy with HTTPS
- Use IAM roles with minimal required permissions
- Regular security group audits
- Monitor scaler logs for suspicious activity

## 🐛 Troubleshooting

### Common Issues

1. **Terraform fails with permission errors**
   ```bash
   # Check AWS credentials
   aws sts get-caller-identity
   # Verify IAM permissions for EC2, Auto Scaling, VPC
   ```

2. **Scaler service not receiving webhooks**
   ```bash
   # Check service status
   sudo systemctl status gpu-scaler
   # Check logs
   sudo journalctl -u gpu-scaler -f
   ```

3. **Nodes not joining Slurm cluster**
   ```bash
   # Check munge key synchronization
   # Verify slurm.conf consistency
   # Check network connectivity to head node
   ```

### Logs

- Scaler service: `/var/log/gpu-scaler.log`
- Systemd service: `journalctl -u gpu-scaler`
- Terraform: `terraform-scale/` directory

## 📊 Monitoring

### Metrics Available

- `/health` endpoint provides service health
- Terraform outputs via `/status` endpoint
- Integration with Prometheus for full observability

### Dashboards

Consider creating Grafana dashboards for:
- Slurm queue metrics
- AWS cost tracking
- GPU utilization
- Scaling events timeline

## 🔄 Scaling Behavior

### Scale Up Triggers
- Pending jobs > threshold (configurable)
- GPU partition demand
- Custom Prometheus rules

### Scale Down Triggers
- No pending jobs for extended period
- Low utilization metrics
- Manual intervention

### Cooldown Periods
- 5-minute cooldown between scaling operations
- Prevents rapid scaling oscillations
- Configurable per operation type

## 🏷️ Cost Management

### Cost Controls
- Maximum instance limits in ASG
- Automatic scale-down triggers
- Cost monitoring alerts

### Optimization Tips
- Use Spot instances for non-critical workloads
- Set appropriate scale-down timeouts
- Monitor usage patterns to optimize instance types

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes and add tests
4. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

For issues and questions:
1. Check the troubleshooting section
2. Review logs for error details
3. Open an issue with detailed information

---

**⚠️ Important**: This system can incur AWS charges. Always monitor your usage and set up billing alerts.
