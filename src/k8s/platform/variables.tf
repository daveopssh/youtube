variable "aws_region" {
  description = "AWS region in which to create the demo VPC and EKS cluster"
  type        = string
  default     = "eu-west-1"
  nullable    = false
}

variable "aws_profile" {
  description = "AWS shared-config profile used for the demo"
  type        = string
  default     = "personal"
  nullable    = false
}

variable "name" {
  description = "Name used for the demo VPC and EKS cluster"
  type        = string
  default     = "platform"
  nullable    = false
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the demo VPC"
  type        = string
  default     = "10.42.0.0/16"
  nullable    = false
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to reach the public EKS API endpoint; use your public IP as a /32"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  nullable    = false

  validation {
    condition     = length(var.allowed_cidr_blocks) > 0 && alltrue([for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "At least one valid CIDR block must be provided."
  }
}

variable "route53_zone_name" {
  description = "Existing public Route53 zone used by External DNS and cert-manager"
  type        = string
  default     = "demo.daveops.sh"
  nullable    = false
}

variable "cert_manager_email" {
  description = "Email address used for the Let's Encrypt ACME account"
  type        = string
  nullable    = false
  default     = "admin@daveops.sh"
}

variable "nginx_hostname" {
  description = "Public hostname for the Nginx demo"
  type        = string
  default     = "nginx.demo.daveops.sh"
  nullable    = false
}
