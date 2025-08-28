# Create a ZIP archive of the Lambda function code using the archive_file data source
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../src/image-processor"
  output_path = "${path.module}/image-processor.zip"
}

# S3 Source Bucket with Free Tier optimization
resource "aws_s3_bucket" "source_bucket" {
  bucket = "${var.project_name}-source-${random_id.bucket_suffix.hex}"
  
  tags = {
    Name        = "${var.project_name}-source"
    Owner       = var.owner_tag
    Project     = var.project_name
    Environment = "FreeTier"
  }
}

# Enable versioning for safety
resource "aws_s3_bucket_versioning" "source_bucket" {
  bucket = aws_s3_bucket.source_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Destination Bucket
resource "aws_s3_bucket" "destination_bucket" {
  bucket = "${var.project_name}-destination-${random_id.bucket_suffix.hex}"
  
  tags = {
    Name        = "${var.project_name}-destination"
    Owner       = var.owner_tag
    Project     = var.project_name
    Environment = "FreeTier"
  }
}

# Lifecycle policy to automatically delete old processed images after 7 days
resource "aws_s3_bucket_lifecycle_configuration" "destination_bucket" {
  bucket = aws_s3_bucket.destination_bucket.id

  rule {
    id     = "delete-old-thumbnails"
    status = "Enabled"

    expiration {
      days = 7
    }

    filter {
      prefix = "thumbnails/"
    }
  }
}

# Random suffix for bucket names to ensure global uniqueness
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-lambda-role"

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
  
  tags = {
    Owner   = var.owner_tag
    Project = var.project_name
  }
}

# IAM Policy for Lambda
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.source_bucket.arn}/*",
          "${aws_s3_bucket.destination_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          aws_sns_topic.notifications.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda Function with Free Tier optimized configuration
resource "aws_lambda_function" "image_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.project_name}-processor"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "app.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  timeout     = 28
  memory_size = 128
  
  environment {
    variables = {
      DESTINATION_BUCKET = aws_s3_bucket.destination_bucket.bucket
      SNS_TOPIC_ARN      = aws_sns_topic.notifications.arn
      SEND_NOTIFICATIONS = "false"
    }
  }

  tags = {
    Owner   = var.owner_tag
    Project = var.project_name
  }

  depends_on = [data.archive_file.lambda_zip]
}

# Lambda Permission for S3
resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.image_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.source_bucket.arn
}

# S3 Bucket Notification to Lambda
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.source_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.image_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".jpg"
  }

  depends_on = [aws_lambda_permission.allow_bucket]
}

# SNS Topic for notifications
resource "aws_sns_topic" "notifications" {
  name = "${var.project_name}-notifications"
  
  tags = {
    Owner   = var.owner_tag
    Project = var.project_name
  }
}


# Outputs
output "source_bucket_name" {
  value = aws_s3_bucket.source_bucket.bucket
}

output "destination_bucket_name" {
  value = aws_s3_bucket.destination_bucket.bucket
}

output "lambda_function_name" {
  value = aws_lambda_function.image_processor.function_name
}

output "instructions" {
  value = <<EOT

Free Tier Image Processing Pipeline deployed successfully!

Next steps:
1. Upload a JPG image to the source bucket: ${aws_s3_bucket.source_bucket.bucket}
2. Check the destination bucket for the processed thumbnail: ${aws_s3_bucket.destination_bucket.bucket}
3. Monitor Lambda function: https://console.aws.amazon.com/lambda/home?region=us-east-1#/functions/${aws_lambda_function.image_processor.function_name}

To avoid charges:
- Processed images are automatically deleted after 7 days
- Notifications are disabled by default
- Remember to run 'terraform destroy' when done testing

EOT
}