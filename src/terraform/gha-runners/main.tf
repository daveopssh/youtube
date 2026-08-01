locals {
  github_runner_prefix = "${var.env_prefix}-gha"

  runner_group_name = "demo"
  runner_labels     = ["youtube", "demote"]

  ssm_parameter_prefix               = "/github-action-runners/${var.env_prefix}/app"
  github_app_id_ssm_name             = "${local.ssm_parameter_prefix}/github_app_id"
  github_app_key_base64_ssm_name     = "${local.ssm_parameter_prefix}/github_app_key_base64"
  github_app_webhook_secret_ssm_name = "${local.ssm_parameter_prefix}/github_app_webhook_secret"

  lambda_key_prefix     = "github-runner/${var.github_runner_module_version}"
  webhook_lambda_s3_key = "${local.lambda_key_prefix}/webhook.zip"
  runners_lambda_s3_key = "${local.lambda_key_prefix}/runners.zip"

  github_app_key_base64_ssm_initial_value = "placeholder-set-via-scripts-put-ssm-parameter-sh"
}

data "aws_region" "current" {}

module "gha_runner_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.10.0"

  bucket = "${var.env_prefix}-gha-runner-lambda"

  versioning = {
    enabled = true
  }

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  attach_deny_insecure_transport_policy = true

  force_destroy = false
}


data "aws_caller_identity" "current" {}

resource "tls_private_key" "runner_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "runner" {
  key_name   = "${local.github_runner_prefix}-key"
  public_key = tls_private_key.runner_ssh.public_key_openssh
}

resource "random_password" "github_webhook_secret" {
  length  = 40
  special = false
}

resource "aws_ssm_parameter" "github_app_id" {
  name  = local.github_app_id_ssm_name
  type  = "SecureString"
  value = var.github_app_id

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "github_app_key_base64" {
  name  = local.github_app_key_base64_ssm_name
  type  = "SecureString"
  value = local.github_app_key_base64_ssm_initial_value

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "github_app_webhook_secret" {
  name  = local.github_app_webhook_secret_ssm_name
  type  = "SecureString"
  value = random_password.github_webhook_secret.result
}

module "github_runner" {
  source  = "github-aws-runners/github-runner/aws"
  version = var.github_runner_module_version

  aws_region = "eu-central-1"
  vpc_id     = "vpc-07d8c9f1bbb50bcc9"
  subnet_ids = ["subnet-00f10e13f2d018c34", "subnet-0e0654779f9751591"]
  prefix     = local.github_runner_prefix

  github_app = {
    id_ssm = {
      arn  = aws_ssm_parameter.github_app_id.arn
      name = aws_ssm_parameter.github_app_id.name
    }
    key_base64_ssm = {
      arn  = aws_ssm_parameter.github_app_key_base64.arn
      name = aws_ssm_parameter.github_app_key_base64.name
    }
    webhook_secret_ssm = {
      arn  = aws_ssm_parameter.github_app_webhook_secret.arn
      name = aws_ssm_parameter.github_app_webhook_secret.name
    }
  }

  lambda_s3_bucket              = module.gha_runner_bucket.s3_bucket_id
  webhook_lambda_s3_key         = local.webhook_lambda_s3_key
  runners_lambda_s3_key         = local.runners_lambda_s3_key
  syncer_lambda_s3_key          = "${local.lambda_key_prefix}/runner-binaries-syncer.zip"
  idle_config                   = var.idle_config
  enable_runner_binaries_syncer = true

  create_service_linked_role_spot         = true
  enable_organization_runners             = false
  enable_ephemeral_runners                = true
  delay_webhook_event                     = 0
  scale_up_reserved_concurrent_executions = -1

  instance_target_capacity_type = var.instance_target_capacity_type
  instance_types                = var.runner_instance_types
  block_device_mappings = [{
    device_name = "/dev/sda1"
    volume_size = 20
  }]
  associate_public_ipv4_address = true

  repository_white_list = ["davejfranco/tf-release"]

  runner_group_name   = local.runner_group_name
  runner_extra_labels = local.runner_labels
  key_name            = aws_key_pair.runner.key_name

  enable_ssm_on_runners = true
}
