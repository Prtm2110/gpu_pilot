output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.gpu.name
}

output "autoscaling_group_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.gpu.arn
}

output "launch_template_id" {
  description = "ID of the Launch Template"
  value       = aws_launch_template.gpu.id
}

output "security_group_id" {
  description = "ID of the security group created for GPU nodes"
  value       = length(var.security_group_ids) > 0 ? "" : aws_security_group.gpu_nodes[0].id
}

output "current_desired_capacity" {
  description = "Current desired capacity of the ASG"
  value       = aws_autoscaling_group.gpu.desired_capacity
}
