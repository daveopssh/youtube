## Pasos

1. Crear bucket para funciones lambda y parameter store para la configuracion
```hcl

module "gha_runner_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.10.0"

  bucket = local.lambda_artifacts_bucket_name

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
  value = local.github_app_id

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "github_app_key_base64" {
  name  = local.github_app_key_base64_ssm_name
  type  = "SecureString"
  value = "placeholder"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "github_app_webhook_secret" {
  name  = local.github_app_webhook_secret_ssm_name
  type  = "SecureString"
  value = random_password.github_webhook_secret.result
}
```

2. Create Github app

2.1 Ir a settings the perfil -> Developer Settings, Create Github App
2.2 Darle un nombre EJ: `gha-tf-runner-demo`
2.3 Homepage URL puede ser cualqueir `https://runner.daveops.sh`
2.4 Desactiva Webhook por ahora 
2.5 Permisos 
```text
Permissions for all runners:
Repository:
Actions: Read-only (check for queued jobs)
Checks: Read-only (receive events for new builds)
Metadata: Read-only (default/required)
```
2.6 Crear App 
2.7 Copia AppID `4154197` y clientID: `Iv23liHz711LMC1aMtvK` 
2.8 Genera new client secret 

### Lambdas 
Once bucket is deployed 
```bash
./publish-github-runner-lambdas.sh s3://demo-gha-runner-lambda --tag v7.7.0 --profile personal

```
