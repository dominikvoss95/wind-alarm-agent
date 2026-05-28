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

# EventBridge rule for scheduled execution
resource "aws_cloudwatch_event_rule" "morning_check" {
  name                = "wind-alarm-morning-check"
  description         = "Triggers wind alarm every 5 minutes between 5:00 and 7:00 CEST (3:00 - 5:00 UTC)"
  schedule_expression = "cron(*/5 3-4 * * ? *)"
}

resource "aws_cloudwatch_event_target" "trigger_kochelsee" {
  rule      = aws_cloudwatch_event_rule.morning_check.name
  target_id = "WindAlarmKochelsee"
  arn       = aws_lambda_function.wind_alarm.arn
  input     = jsonencode({
    location  = "kochelsee"
    threshold = 10.0
  })
}

resource "aws_cloudwatch_event_target" "trigger_gardasee" {
  rule      = aws_cloudwatch_event_rule.morning_check.name
  target_id = "WindAlarmGardasee"
  arn       = aws_lambda_function.wind_alarm.arn
  input     = jsonencode({
    location  = "gardasee"
    threshold = 12.0
  })
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.wind_alarm.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.morning_check.arn
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

