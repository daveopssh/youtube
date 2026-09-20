data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs                 = slice(data.aws_availability_zones.available.names, 0, 2)
  allowed_cidr_blocks = ["90.185.76.231/32"]
  tags = {
    Environment = "demo"
    Project     = "infrak8s"
    Terraform   = "true"
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.2"

  name = var.name
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = [
    for index, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, index)
  ]
  public_subnets = [
    for index, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, index + length(local.azs))
  ]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  private_subnet_tags = merge(local.tags, {
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery"          = var.name
  })
  public_subnet_tags = merge(local.tags, {
    "kubernetes.io/role/elb" = "1"
  })

  tags = local.tags
}

resource "aws_secretsmanager_secret" "nginx_demo" {
  name                    = "${var.name}/nginx-demo"
  description             = "Non-sensitive environment-variable demo for Nginx"
  recovery_window_in_days = 0

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "nginx_demo" {
  secret_id = aws_secretsmanager_secret.nginx_demo.id
  secret_string = jsonencode({
    demo-secret = "hello-from-secrets-manager"
  })
}

module "platform" {
  source = "git::https://github.com/daveopssh/tf-eks-platform.git?ref=4c29b9b7f45fb15c7693dedfe5a9fa258fae4876"

  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.private_subnets
  aws_region          = var.aws_region
  environment         = "demo"
  cluster_name        = var.name
  project_name        = "infrak8s"
  route53_zone_name   = var.route53_zone_name
  cert_manager_email  = var.cert_manager_email
  allowed_cidr_blocks = local.allowed_cidr_blocks
  external_secrets_manager_arns = [
    aws_secretsmanager_secret.nginx_demo.arn,
  ]

  node_group_instance_types = ["t3.medium"]
  node_group_min_size       = 2
  node_group_desired_size   = 2
  node_group_max_size       = 2

  enable_aws_load_balancer_controller = true
  enable_traefik                      = true
  enable_karpenter                    = true
  enable_monitoring                   = true

  tags = local.tags
}

resource "helm_release" "nginx_demo" {
  name             = "nginx-demo"
  chart            = "${path.module}/app"
  namespace        = "nginx-demo"
  create_namespace = true

  atomic          = true
  cleanup_on_fail = true
  timeout         = 900
  wait            = true

  values = [
    yamlencode({
      hostname      = var.nginx_hostname
      awsSecretName = aws_secretsmanager_secret.nginx_demo.name
    })
  ]

  depends_on = [
    module.platform,
    aws_secretsmanager_secret_version.nginx_demo,
  ]
}
