variable "aws_profile" {}
data "aws_caller_identity" "current" {}

variable "aws_region" {
  default = "us-east-1"
}

provider "aws" {
  region = "${var.aws_region}"
  profile = "${var.aws_profile}"
}

////
// general setup
//

// the bucket must be configured with the -backend-config flag on `terraform init`

terraform {
  backend "s3" {
    key = "x-ray-profiling-experiment/app.tfstate"
  }
}

resource "aws_iam_role" "x_ray_profiling_experiment" {
  name = "x-ray-profiling-experiment"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "x_ray_profiling_experiment" {
  name   = "x-ray-profiling-experiment"
  role   = "${aws_iam_role.x_ray_profiling_experiment.name}"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:DescribeLogStreams",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:*:*:*"
        },
        {
            "Effect": "Allow",
            "Action": "logs:CreateLogGroup",
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": "es:*",
            "Resource": "arn:aws:es:*:*:*"
        }
    ]
}
EOF
  depends_on = [
    "aws_iam_role.x_ray_profiling_experiment"
  ]
}

data "archive_file" "lambda_zip" {
  type = "zip"
  source_dir = "./target"
  output_path = "./lambda.zip"
}

resource "aws_lambda_function" "x_ray_profiling_experiment" {
  function_name = "x-ray-profiling-experiment"
  description = "Manages hca log elasticsearch indexes"
  filename = "${data.archive_file.lambda_zip.output_path}"
  role = "${aws_iam_role.x_ray_profiling_experiment.arn}"
  handler = "app.handler"
  runtime = "python3.6"
  memory_size = 256
  timeout = 120
  source_code_hash = "${base64sha256(file("${data.archive_file.lambda_zip.output_path}"))}"
  depends_on = [
    "data.archive_file.lambda_zip"
  ]
}


////
//  Timer
//

resource "aws_cloudwatch_event_rule" "x_ray_profiling_experiment" {
  name = "x-ray-profiling-experiment"
  description = "Trigger the x-ray-profiling-experiment app"
  schedule_expression = "rate(2 days)"
}

resource "aws_lambda_permission" "dss" {
  statement_id = "AllowExecutionFromCloudWatch"
  principal = "events.amazonaws.com"
  action = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.x_ray_profiling_experiment.function_name}"
  source_arn = "${aws_cloudwatch_event_rule.x_ray_profiling_experiment.arn}"
  depends_on = [
    "aws_lambda_function.x_ray_profiling_experiment"
  ]
}

resource "aws_cloudwatch_event_target" "dss" {
  rule      = "${aws_cloudwatch_event_rule.x_ray_profiling_experiment.name}"
  target_id = "invoke-x-ray-profiling-experiment"
  arn       = "${aws_lambda_function.x_ray_profiling_experiment.arn}"
}
