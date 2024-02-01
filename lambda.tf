data "aws_caller_identity" "current" {}

locals {
    account_id = data.aws_caller_identity.current.account_id
}

# Zip the Lambda function on the fly
data "archive_file" "source" {
  type        = "zip"
  source_dir  = "lambda-termination/libs"
  output_path = "lambda-termination/management-workspaces-ad-function.zip"
}

# Create S3 bucket that will be used to update lambda ziped code
resource "aws_s3_bucket" "lambda_bucket" {
  bucket        = "lambda-zip-bucket-${random_password.randomstring.result}"
  acl           = "private"
  force_destroy = true
}

# upload lambda zip to s3 and then update lambda function from s3
resource "aws_s3_bucket_object" "file_upload" {
  bucket = "${aws_s3_bucket.lambda_bucket.id}"
  key    = "lambda-function/management-workspaces-ad-function.zip"
  source = "lambda-termination/management-workspaces-ad-function.zip" # its mean it depended on zip
}

#S3 bucket responsible for WorkSpaces creation
resource "aws_s3_bucket" "workspaces_creation_bucket" {
  bucket        = "workspaces-creation-bucket-${random_password.randomstring.result}"
  acl           = "private"
  force_destroy = true
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket      = aws_s3_bucket.workspaces_creation_bucket.id
  eventbridge = true
}

resource "aws_lambda_function" "lambda_creation" {
  function_name = "create-workspaces-ad-function"
  s3_bucket   = "${aws_s3_bucket.lambda_bucket.id}"
  s3_key      = "${aws_s3_bucket_object.file_upload.key}" 
  source_code_hash = "${base64sha256(data.archive_file.source.output_path)}"
  role    = aws_iam_role.iam_for_lambda.arn
  handler = "lambda_creation.lambda_handler"
  runtime = "python3.8"
  timeout = 10
  
  vpc_config {
    subnet_ids = [aws_subnet.private_subnet.id,aws_subnet.private_subnet_2.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      DNS_HOSTNAME = "${join(",",aws_directory_service_directory.aws_ad.dns_ip_addresses)}",
      DIRECTORY_NAME = aws_directory_service_directory.aws_ad.name,
      DIRECTORY_ID = aws_directory_service_directory.aws_ad.id,
      SSM_AD_ADMIN = aws_secretsmanager_secret.ad_admin.name
    }
  }
}

resource "random_password" "randomstring" {
  length           = 3
  special          = false
  upper            = false
}

# Lambda remove computer from AD
resource "aws_lambda_function" "lambda" {
  function_name = "remove-workspaces-ad-function"
  s3_bucket   = "${aws_s3_bucket.lambda_bucket.id}"
  s3_key      = "${aws_s3_bucket_object.file_upload.key}" 
  source_code_hash = "${base64sha256(data.archive_file.source.output_path)}"
  role    = aws_iam_role.iam_for_lambda.arn
  handler = "lambda_termination.lambda_handler"
  runtime = "python3.8"
  timeout = 10
  
  vpc_config {
    subnet_ids = [aws_subnet.private_subnet.id,aws_subnet.private_subnet_2.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      DNS_HOSTNAME = "${join(",",aws_directory_service_directory.aws_ad.dns_ip_addresses)}",
      DIRECTORY_NAME = aws_directory_service_directory.aws_ad.name,
      DIRECTORY_ID = aws_directory_service_directory.aws_ad.id,
      SSM_AD_ADMIN = aws_secretsmanager_secret.ad_admin.name
    }
  }
}

###IAM Role for Lambda
resource "aws_iam_role" "iam_for_lambda" {
  name               = "lambda-ad-management-iam-role"
  assume_role_policy = data.aws_iam_policy_document.policy.json
}

data "aws_iam_policy_document" "policy" {
  statement {
    sid    = ""
    effect = "Allow"
    principals {
      identifiers = ["lambda.amazonaws.com"]
      type        = "Service"
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy" "test_policy" {
  name = "ad-management-lambda-policy"
  role = aws_iam_role.iam_for_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:*"
        ]
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.workspaces_creation_bucket.arn}/*"
      },
      {
        Action = [  
          "workspaces:*"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:workspaces:us-east-1:${local.account_id}:workspace/*"
      },
      {
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:us-east-1:${local.account_id}:log-group:/aws/lambda/remove-computer-ad-function:*"
      },
      {
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:AttachNetworkInterface"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:secretsmanager:us-east-1:${local.account_id}:secret:dev/ADcredential*"
      },
      {
        Action = [
          "kms:Describe*"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:kms:us-east-1:${local.account_id}:key/*"
      },
      {
        Action = [
          "ds:ResetUserPassword"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:ds:us-east-1:${local.account_id}:directory/${aws_directory_service_directory.aws_ad.id}"
      }
    ]
  })
}
