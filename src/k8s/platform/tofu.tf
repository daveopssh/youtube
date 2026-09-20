terraform {
  required_version = ">= 1.11.2"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
}

data "aws_eks_cluster" "platform" {
  name = module.platform.cluster_name

  depends_on = [module.platform]
}

data "aws_eks_cluster_auth" "platform" {
  name = module.platform.cluster_name

  depends_on = [module.platform]
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.platform.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.platform.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.platform.token
  }
}
