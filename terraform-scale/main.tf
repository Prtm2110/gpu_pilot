terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# Data sources for existing VPC and subnets (if needed)
data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

data "aws_subnets" "default" {
  count = length(var.subnet_ids) == 0 ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id]
  }
}

# Security group for GPU instances
resource "aws_security_group" "gpu_nodes" {
  count       = length(var.security_group_ids) == 0 ? 1 : 0
  name_prefix = "hpc-gpu-sg-"
  vpc_id      = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }

  # Slurm communication
  ingress {
    from_port   = 6817
    to_port     = 6818
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }

  # Munge authentication
  ingress {
    from_port   = 6809
    to_port     = 6809
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "hpc-gpu-security-group"
  }
}

# Launch template for GPU instances
resource "aws_launch_template" "gpu" {
  name_prefix   = "hpc-gpu-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name != "" ? var.key_name : null

  vpc_security_group_ids = length(var.security_group_ids) > 0 ? var.security_group_ids : [aws_security_group.gpu_nodes[0].id]

  user_data = base64encode(file("${path.module}/user-data.sh"))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "hpc-gpu-node"
      Type = "slurm-compute"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "gpu" {
  name                = "hpc-gpu-asg"
  vpc_zone_identifier = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.default[0].ids
  target_group_arns   = []
  health_check_type   = "EC2"
  health_check_grace_period = 300

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.scale_up ? var.desired_capacity_up : 0

  launch_template {
    id      = aws_launch_template.gpu.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "hpc-gpu-asg"
    propagate_at_launch = false
  }

  tag {
    key                 = "Environment"
    value               = "hpc"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}
