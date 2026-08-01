output "github_app_ssm_parameter_names" {
  description = "SSM parameter names used for GitHub App credentials."
  value = {
    app_id         = aws_ssm_parameter.github_app_id.name
    key_base64     = aws_ssm_parameter.github_app_key_base64.name
    webhook_secret = aws_ssm_parameter.github_app_webhook_secret.name
  }
}

output "key_pair_name" {
  description = "EC2 key pair name attached to runner instances."
  value       = aws_key_pair.runner.key_name
}

output "lambda_artifacts_bucket_name" {
  description = "S3 bucket name used for GitHub runner lambda artifacts."
  value       = module.gha_runner_bucket.s3_bucket_id
}

output "lambda_artifact_keys" {
  description = "S3 object keys expected for lambda artifacts."
  value = {
    webhook = local.webhook_lambda_s3_key
    runners = local.runners_lambda_s3_key
  }
}

output "webhook" {
  description = "gha runner webhook"
  value       = module.github_runner.webhook.endpoint
}
