# Infrastructure for Wind Alarm Agent

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

# ECR Repository for container images
resource "aws_ecr_repository" "app" {
  name                 = var.app_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

# IAM Role for Lambda execution
resource "aws_iam_role" "lambda_role" {
  name = "${var.app_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# IAM Policy for resource access
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.app_name}-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["bedrock:InvokeModel"]
        Resource = "arn:aws:bedrock:*::foundation-model/amazon.nova-lite-v1:0"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query"
        ]
        Resource = "arn:aws:dynamodb:${var.region}:*:table/wind-alarm-*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject"
        ]
        Resource = "arn:aws:s3:::wind-alarm-web-assets-${data.aws_caller_identity.current.account_id}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "WindAlarm"
          }
        }
      }
    ]
  })
}

# S3 Bucket for public static web assets (measurements.json, history_*.json)
resource "aws_s3_bucket" "web_assets" {
  bucket        = "wind-alarm-web-assets-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "web_assets_block" {
  bucket = aws_s3_bucket.web_assets.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "web_assets_policy" {
  depends_on = [aws_s3_bucket_public_access_block.web_assets_block]
  bucket     = aws_s3_bucket.web_assets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.web_assets.arn}/*"
      }
    ]
  })
}

# DynamoDB Table for Historical Data
resource "aws_dynamodb_table" "knowledge_base" {
  name           = "wind-alarm-knowledge-base"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "location_id"
  range_key      = "observed_at"

  attribute {
    name = "location_id"
    type = "S"
  }

  attribute {
    name = "observed_at"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Environment = "production"
    Application = var.app_name
  }
}

# Lambda Function
resource "aws_lambda_function" "wind_alarm" {
  function_name = var.app_name
  role          = aws_iam_role.lambda_role.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.app.repository_url}:latest"
  timeout       = 300
  memory_size   = 2048

  environment {
    variables = {
      USE_AWS                 = "true"
      WIND_ALARM_ORCHESTRATOR = "langgraph"
      WIND_ALARM_KB_TABLE     = aws_dynamodb_table.knowledge_base.name
      WIND_ALARM_BUCKET       = aws_s3_bucket.web_assets.id
    }
  }
}

# Primary scheduler. GitHub Actions cron is best-effort and is only a backup.
# Hours are the union of CET and CEST so 05:00-08:00 Berlin (Kochelsee) and
# 05:00-10:00 Berlin (Gardasee) are inside the schedule all year.
# cron(*/5 3-7) is 03:00-07:55 UTC: 04:00-08:55 CET and 05:00-09:55 CEST.
# cron(*/5 3-9) is 03:00-09:55 UTC: 04:00-10:55 CET and 05:00-11:55 CEST.
resource "aws_cloudwatch_event_rule" "kochelsee_check" {
  name                = "wind-alarm-kochelsee"
  description         = "Kochelsee every 5 minutes, UTC hours 3-7 (covers 05:00-08:00 Berlin in CET and CEST)"
  schedule_expression = "cron(*/5 3-7 * * ? *)"
}

resource "aws_cloudwatch_event_rule" "gardasee_check" {
  name                = "wind-alarm-gardasee"
  description         = "Gardasee every 5 minutes, UTC hours 3-9 (covers 05:00-10:00 Berlin in CET and CEST)"
  schedule_expression = "cron(*/5 3-9 * * ? *)"
}

resource "aws_cloudwatch_event_target" "trigger_kochelsee" {
  rule      = aws_cloudwatch_event_rule.kochelsee_check.name
  target_id = "WindAlarmKochelsee"
  arn       = aws_lambda_function.wind_alarm.arn
  input     = jsonencode({
    location  = "kochelsee"
    threshold = 10.0
  })
}

resource "aws_cloudwatch_event_target" "trigger_gardasee" {
  rule      = aws_cloudwatch_event_rule.gardasee_check.name
  target_id = "WindAlarmGardasee"
  arn       = aws_lambda_function.wind_alarm.arn
  input     = jsonencode({
    location  = "gardasee"
    threshold = 12.0
  })
}

resource "aws_lambda_permission" "allow_kochelsee" {
  statement_id  = "AllowKochelseeSchedule"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.wind_alarm.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.kochelsee_check.arn
}

resource "aws_lambda_permission" "allow_gardasee" {
  statement_id  = "AllowGardaseeSchedule"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.wind_alarm.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.gardasee_check.arn
}

# Dead-man's switch. An hourly invocation publishes SchedulerAlive=1.
# The alarm treats missing data as a breach, so a stopped schedule pages
# even when nobody pushes to the repository. Nights stay quiet because the
# heartbeat still runs. Attach an email or SNS action in the console.
resource "aws_cloudwatch_event_rule" "heartbeat" {
  name                = "wind-alarm-heartbeat"
  description         = "Hourly proof the scheduler is invoking Lambda"
  schedule_expression = "cron(0 * * * ? *)"
}

resource "aws_cloudwatch_event_target" "heartbeat" {
  rule      = aws_cloudwatch_event_rule.heartbeat.name
  target_id = "WindAlarmHeartbeat"
  arn       = aws_lambda_function.wind_alarm.arn
  input     = jsonencode({
    action = "heartbeat"
  })
}

resource "aws_lambda_permission" "allow_heartbeat" {
  statement_id  = "AllowHeartbeatSchedule"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.wind_alarm.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.heartbeat.arn
}

resource "aws_cloudwatch_metric_alarm" "scheduler_alive" {
  alarm_name          = "wind-alarm-scheduler-silent"
  alarm_description   = "No SchedulerAlive metric for two hours. EventBridge is not invoking the wind alarm Lambda."
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "SchedulerAlive"
  namespace           = "WindAlarm"
  period              = 3600
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "breaching"
}

resource "aws_cloudwatch_metric_alarm" "measurement_errors" {
  alarm_name          = "wind-alarm-measurement-errors"
  alarm_description   = "Lambda errors. A run with no fresh station reading returns 500. Missing data does not alarm, so nights are quiet."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.wind_alarm.function_name
  }
}

# EventBridge rule for daily forecast check at 12:00 CEST (10:00 UTC)
resource "aws_cloudwatch_event_rule" "forecast_check" {
  name                = "wind-alarm-forecast-check"
  description         = "Triggers daily wind forecast at 12:00 CEST (10:00 UTC)"
  schedule_expression = "cron(0 10 * * ? *)"
}

resource "aws_cloudwatch_event_target" "forecast_kochelsee" {
  rule      = aws_cloudwatch_event_rule.forecast_check.name
  target_id = "WindForecastKochelsee"
  arn       = aws_lambda_function.wind_alarm.arn
  input     = jsonencode({
    action   = "forecast"
    location = "kochelsee"
  })
}

resource "aws_cloudwatch_event_target" "forecast_gardasee" {
  rule      = aws_cloudwatch_event_rule.forecast_check.name
  target_id = "WindForecastGardasee"
  arn       = aws_lambda_function.wind_alarm.arn
  input     = jsonencode({
    action   = "forecast"
    location = "gardasee"
  })
}

resource "aws_lambda_permission" "allow_forecast_cloudwatch" {
  statement_id  = "AllowForecastExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.wind_alarm.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.forecast_check.arn
}

output "s3_bucket_url" {
  value       = "https://${aws_s3_bucket.web_assets.bucket_regional_domain_name}"
  description = "The public URL of the S3 bucket hosting wind measurements"
}

