output "vpc_id" {
  description = "ID of the VPC created by this demo"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs supplied to the EKS platform module"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs used for internet-facing load balancers"
  value       = module.vpc.public_subnets
}

output "cluster_name" {
  description = "Name of the EKS cluster created by the platform module"
  value       = module.platform.cluster_name
}

output "cluster_endpoint" {
  description = "EKS Kubernetes API endpoint"
  value       = module.platform.cluster_endpoint
}

output "aws_region" {
  description = "AWS region containing the demo"
  value       = var.aws_region
}

output "aws_profile" {
  description = "AWS profile used by the demo"
  value       = var.aws_profile
}

output "route53_zone_name" {
  description = "Public Route53 zone used by the platform"
  value       = var.route53_zone_name
}

output "nginx_hostname" {
  description = "Public hostname for the Nginx demo"
  value       = var.nginx_hostname
}

output "nginx_url" {
  description = "HTTPS URL for the Nginx demo"
  value       = "https://${var.nginx_hostname}"
}

output "kubeconfig_command" {
  description = "Command that configures kubectl for the demo cluster"
  value       = "aws eks update-kubeconfig --profile ${var.aws_profile} --region ${var.aws_region} --name ${module.platform.cluster_name}"
}
