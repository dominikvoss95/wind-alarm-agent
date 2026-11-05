output "plan_role_arn" {
  description = "GitHub Actions repository variable AWS_PLAN_ROLE_ARN. Not a secret."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "GitHub Actions repository variable AWS_APPLY_ROLE_ARN. Not a secret."
  value       = aws_iam_role.apply.arn
}

output "state_bucket_name" {
  description = "GitHub Actions repository variable TF_STATE_BUCKET. Not a secret."
  value       = aws_s3_bucket.state.bucket
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider trusted by the GitHub Actions roles."
  value       = local.oidc_provider_arn
}

output "github_environment" {
  description = "GitHub environment required before apply. Protect it with reviewers."
  value       = local.github_environment
}

output "github_actions_variables" {
  description = "Repository variables (Settings, Secrets and variables, Actions, Variables). Do not store these as secrets."
  value = {
    AWS_PLAN_ROLE_ARN  = aws_iam_role.plan.arn
    AWS_APPLY_ROLE_ARN = aws_iam_role.apply.arn
    TF_STATE_BUCKET    = aws_s3_bucket.state.bucket
  }
}
