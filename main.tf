provider "aws" {
  alias  = "source"
  region = var.region
}

data "aws_region" "current" {
  provider = aws.source
}

data "aws_caller_identity" "current" {
  provider = aws.source
}

# Source Log Group
resource "aws_cloudwatch_log_group" "source_log_group" {
  provider = aws.source
  name     = var.source_log_group_name
}

# Lambda Role
resource "aws_iam_role" "log_forwarder_role" {
  provider = aws.source
  name     = "LogForwarderLambdaRole"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Lambda Role Policy
resource "aws_iam_role_policy" "log_forwarder_policy" {
  provider = aws.source
  role     = aws_iam_role.log_forwarder_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:PutRecord",
          "kinesis:PutRecords"
        ]
        Resource = var.kinesis_stream_arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"
        ]
      }
    ]
  })
}

# Lambda Function
resource "aws_lambda_function" "log_forwarder" {
  provider      = aws.source
  function_name = var.log_forwarder_lambda_name
  handler       = "index.handler"
  runtime       = "python3.8"
  role          = aws_iam_role.log_forwarder_role.arn
  filename      = "lambda/log_forwarder.zip"

  environment {
    variables = {
      KINESIS_STREAM_ARN = var.kinesis_stream_arn
    }
  }
}

# Lambda Permission for CloudWatch
resource "aws_lambda_permission" "allow_cloudwatch" {
  provider      = aws.source
  statement_id  = "AllowCloudWatchLogsToInvokeLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.log_forwarder.function_name
  principal     = "logs.${data.aws_region.current.name}.amazonaws.com"
  source_arn    = "${aws_cloudwatch_log_group.source_log_group.arn}:*"
}

# CloudWatch Role
resource "aws_iam_role" "cloudwatch_role" {
  provider = aws.source
  name     = var.log_subscription_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# CloudWatch to Lambda Policy
resource "aws_iam_role_policy" "cloudwatch_lambda_policy" {
  provider = aws.source
  name     = "CloudWatchToLambdaPolicy"
  role     = aws_iam_role.cloudwatch_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.log_forwarder.arn
        ]
      }
    ]
  })
}

# Kinesis Policy
resource "aws_iam_role_policy" "cloudwatch_kinesis_policy" {
  provider = aws.source
  name     = "CloudWatchToKinesisPolicy"
  role     = aws_iam_role.cloudwatch_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:PutRecord"
        ]
        Resource = [
          var.kinesis_stream_arn
        ]
      }
    ]
  })
}

# Subscription Filter
resource "aws_cloudwatch_log_subscription_filter" "log_subscription" {
  provider        = aws.source
  name            = "CentralLogStreamSubscription"
  log_group_name  = aws_cloudwatch_log_group.source_log_group.name
  filter_pattern  = ""
  destination_arn = aws_lambda_function.log_forwarder.arn
  role_arn        = aws_iam_role.cloudwatch_role.arn

  depends_on = [
    aws_lambda_permission.allow_cloudwatch,
    aws_iam_role_policy.cloudwatch_lambda_policy,
    aws_iam_role_policy.cloudwatch_kinesis_policy
  ]
}

# Variables file
variable "region" {
  description = "AWS region"
  type        = string
}

variable "source_log_group_name" {
  description = "Name of the source CloudWatch Log Group"
  type        = string
}

variable "kinesis_stream_arn" {
  description = "ARN of the Kinesis stream"
  type        = string
}

variable "log_forwarder_lambda_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "log_subscription_role_name" {
  description = "Name of the log subscription IAM role"
  type        = string
}
