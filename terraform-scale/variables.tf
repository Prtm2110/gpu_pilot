variable "scale_up" {
  type        = bool
  description = "Whether to scale up (true) or scale down (false) the GPU instances"
  default     = false
}

variable "region" {
  type        = string
  description = "AWS region for resources"
  default     = "us-west-2"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where instances will be launched"
  default     = ""
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for the auto scaling group"
  default     = []
}

variable "ami_id" {
  type        = string
  description = "AMI ID for GPU instances (should have CUDA and Slurm pre-installed)"
  default     = "ami-0c02fb55956c7d316"  # Amazon Linux 2 - replace with your custom AMI
}

variable "instance_type" {
  type        = string
  description = "Instance type for GPU nodes"
  default     = "g4dn.xlarge"
}

variable "key_name" {
  type        = string
  description = "EC2 Key Pair name for SSH access"
  default     = ""
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security group IDs for the instances"
  default     = []
}

variable "min_size" {
  type        = number
  description = "Minimum number of instances in ASG"
  default     = 0
}

variable "max_size" {
  type        = number
  description = "Maximum number of instances in ASG"
  default     = 10
}

variable "desired_capacity_up" {
  type        = number
  description = "Desired capacity when scaling up"
  default     = 2
}
