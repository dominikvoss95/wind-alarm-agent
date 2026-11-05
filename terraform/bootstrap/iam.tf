# Two roles, both limited to this repository and to .github/workflows/terraform.yml.
# Plan can be assumed from a pull request or from main. It cannot change infrastructure.
# Apply can be assumed only from main, and only by the production environment job.
# Neither role can edit this bootstrap stack, the OIDC provider, or these roles.

data "aws_iam_policy_document" "plan_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:repository"
      values   = [local.github_repository]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${local.github_repository}:pull_request",
        "repo:${local.github_repository}:ref:refs/heads/main",
      ]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:workflow_ref"
      values   = [local.workflow_ref_any]
    }
  }
}

data "aws_iam_policy_document" "apply_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:repository"
      values   = [local.github_repository]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.github_repository}:environment:${local.github_environment}"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:ref"
      values   = ["refs/heads/main"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:workflow_ref"
      values   = [local.workflow_ref_main]
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "${local.name_prefix}-gha-plan"
  description          = "GitHub Actions Terraform plan for wind-alarm-agent. Read-only on the app stack."
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600

  tags = {
    Project   = local.name_prefix
    ManagedBy = "terraform-bootstrap"
    Purpose   = "github-actions-plan"
  }
}

resource "aws_iam_role" "apply" {
  name                 = "${local.name_prefix}-gha-apply"
  description          = "GitHub Actions Terraform apply for wind-alarm-agent. Limited to the app stack."
  assume_role_policy   = data.aws_iam_policy_document.apply_trust.json
  max_session_duration = 3600

  tags = {
    Project   = local.name_prefix
    ManagedBy = "terraform-bootstrap"
    Purpose   = "github-actions-apply"
  }
}

data "aws_iam_policy_document" "state" {
  statement {
    sid    = "StateList"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [local.state_bucket_arn]
  }

  statement {
    sid    = "StateObject"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = ["${local.state_bucket_arn}/${local.state_key}"]
  }

  statement {
    sid    = "StateLock"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${local.state_bucket_arn}/${local.state_key}.tflock"]
  }
}

data "aws_iam_policy_document" "infra_read" {
  statement {
    sid    = "EcrRead"
    effect = "Allow"
    actions = [
      "ecr:DescribeRepositories",
      "ecr:ListTagsForResource",
      "ecr:GetRepositoryPolicy",
      "ecr:GetLifecyclePolicy",
    ]
    resources = [local.ecr_repository_arn]
  }

  statement {
    sid    = "IamRead"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:ListRolePolicies",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListRoleTags",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = [local.lambda_role_arn]
  }

  statement {
    sid    = "LambdaRead"
    effect = "Allow"
    actions = [
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:GetFunctionCodeSigningConfig",
      "lambda:GetFunctionConcurrency",
      "lambda:GetFunctionEventInvokeConfig",
      "lambda:GetFunctionRecursionConfig",
      "lambda:GetRuntimeManagementConfig",
      "lambda:GetPolicy",
      "lambda:ListTags",
      "lambda:ListVersionsByFunction",
    ]
    resources = [local.lambda_function_arn]
  }

  statement {
    sid    = "WebBucketRead"
    effect = "Allow"
    actions = [
      "s3:GetAccelerateConfiguration",
      "s3:GetBucketAcl",
      "s3:GetBucketCORS",
      "s3:GetBucketLocation",
      "s3:GetBucketLogging",
      "s3:GetBucketNotification",
      "s3:GetBucketObjectLockConfiguration",
      "s3:GetBucketOwnershipControls",
      "s3:GetBucketPolicy",
      "s3:GetBucketPolicyStatus",
      "s3:GetBucketPublicAccessBlock",
      "s3:GetBucketRequestPayment",
      "s3:GetBucketTagging",
      "s3:GetBucketVersioning",
      "s3:GetBucketWebsite",
      "s3:GetEncryptionConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:GetReplicationConfiguration",
      "s3:ListBucket",
    ]
    resources = [local.web_bucket_arn]
  }

  statement {
    sid    = "DynamoRead"
    effect = "Allow"
    actions = [
      "dynamodb:DescribeContinuousBackups",
      "dynamodb:DescribeTable",
      "dynamodb:DescribeTimeToLive",
      "dynamodb:ListTagsOfResource",
    ]
    resources = [local.dynamodb_table_arn]
  }

  statement {
    sid    = "EventsRead"
    effect = "Allow"
    actions = [
      "events:DescribeRule",
      "events:ListTagsForResource",
      "events:ListTargetsByRule",
    ]
    resources = [local.event_rule_arn]
  }

  statement {
    sid    = "AlarmsRead"
    effect = "Allow"
    actions = [
      "cloudwatch:DescribeAlarms",
      "cloudwatch:ListTagsForResource",
    ]
    resources = [local.alarm_arn]
  }
}

data "aws_iam_policy_document" "infra_write" {
  statement {
    sid    = "EcrWrite"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchDeleteImage",
      "ecr:BatchGetImage",
      "ecr:CreateRepository",
      "ecr:DeleteLifecyclePolicy",
      "ecr:DeleteRepository",
      "ecr:DeleteRepositoryPolicy",
      "ecr:GetDownloadUrlForLayer",
      "ecr:ListImages",
      "ecr:PutImageScanningConfiguration",
      "ecr:PutImageTagMutability",
      "ecr:PutLifecyclePolicy",
      "ecr:SetRepositoryPolicy",
      "ecr:TagResource",
      "ecr:UntagResource",
    ]
    resources = [local.ecr_repository_arn]
  }

  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "IamWriteLambdaRole"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:PutRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:UpdateRole",
    ]
    resources = [local.lambda_role_arn]
  }

  statement {
    sid       = "PassLambdaRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [local.lambda_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com"]
    }
  }

  statement {
    sid    = "LambdaWrite"
    effect = "Allow"
    actions = [
      "lambda:AddPermission",
      "lambda:CreateFunction",
      "lambda:DeleteFunction",
      "lambda:PutFunctionCodeSigningConfig",
      "lambda:RemovePermission",
      "lambda:TagResource",
      "lambda:UntagResource",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
    ]
    resources = [local.lambda_function_arn]
  }

  statement {
    sid    = "WebBucketWrite"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:DeleteBucketPolicy",
      "s3:PutBucketAcl",
      "s3:PutBucketOwnershipControls",
      "s3:PutBucketPolicy",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketTagging",
      "s3:PutEncryptionConfiguration",
    ]
    resources = [local.web_bucket_arn]
  }

  statement {
    sid    = "WebBucketEmpty"
    effect = "Allow"
    actions = [
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
    ]
    resources = ["${local.web_bucket_arn}/*"]
  }

  statement {
    sid    = "DynamoWrite"
    effect = "Allow"
    actions = [
      "dynamodb:CreateTable",
      "dynamodb:DeleteTable",
      "dynamodb:TagResource",
      "dynamodb:UntagResource",
      "dynamodb:UpdateContinuousBackups",
      "dynamodb:UpdateTable",
      "dynamodb:UpdateTimeToLive",
    ]
    resources = [local.dynamodb_table_arn]
  }

  statement {
    sid    = "EventsWrite"
    effect = "Allow"
    actions = [
      "events:DeleteRule",
      "events:DisableRule",
      "events:EnableRule",
      "events:PutRule",
      "events:PutTargets",
      "events:RemoveTargets",
      "events:TagResource",
      "events:UntagResource",
    ]
    resources = [local.event_rule_arn]
  }

  statement {
    sid    = "AlarmsWrite"
    effect = "Allow"
    actions = [
      "cloudwatch:DeleteAlarms",
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:TagResource",
      "cloudwatch:UntagResource",
    ]
    resources = [local.alarm_arn]
  }
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "terraform-state"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.state.json
}

resource "aws_iam_role_policy" "plan_infra" {
  name   = "wind-alarm-read"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.infra_read.json
}

resource "aws_iam_role_policy" "apply_state" {
  name   = "terraform-state"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.state.json
}

resource "aws_iam_role_policy" "apply_read" {
  name   = "wind-alarm-read"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.infra_read.json
}

resource "aws_iam_role_policy" "apply_write" {
  name   = "wind-alarm-write"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.infra_write.json
}
