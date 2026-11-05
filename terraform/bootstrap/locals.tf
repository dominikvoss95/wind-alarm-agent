data "aws_caller_identity" "current" {}

locals {
  github_repository  = "dominikvoss95/wind-alarm-agent"
  github_workflow    = ".github/workflows/terraform.yml"
  github_environment = "production"
  name_prefix        = "wind-alarm-agent"
  state_key          = "wind-alarm-agent/aws.tfstate"

  account_id        = data.aws_caller_identity.current.account_id
  state_bucket_name = "wind-alarm-agent-tfstate-${local.account_id}"
  state_bucket_arn  = "arn:aws:s3:::${local.state_bucket_name}"

  ecr_repository_arn  = "arn:aws:ecr:${var.region}:${local.account_id}:repository/${local.name_prefix}"
  lambda_function_arn = "arn:aws:lambda:${var.region}:${local.account_id}:function:${local.name_prefix}"
  lambda_role_arn     = "arn:aws:iam::${local.account_id}:role/${local.name_prefix}-lambda-role"
  dynamodb_table_arn  = "arn:aws:dynamodb:${var.region}:${local.account_id}:table/wind-alarm-knowledge-base"
  web_bucket_arn      = "arn:aws:s3:::wind-alarm-web-assets-${local.account_id}"
  event_rule_arn      = "arn:aws:events:${var.region}:${local.account_id}:rule/wind-alarm-*"
  alarm_arn           = "arn:aws:cloudwatch:${var.region}:${local.account_id}:alarm:wind-alarm-*"

  oidc_provider_arn = (
    var.create_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com"
  )

  workflow_ref_main = "${local.github_repository}/${local.github_workflow}@refs/heads/main"
  workflow_ref_any  = "${local.github_repository}/${local.github_workflow}@*"
}
