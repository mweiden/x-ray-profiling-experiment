variable "aws_profile" {}
data "aws_caller_identity" "current" {}

variable "aws_region" {
  default = "us-east-1"
}

provider "aws" {
  region = "${var.aws_region}"
  profile = "${var.aws_profile}"
}

terraform {
  backend "s3" {
    key = "x-ray-profiling-experiment/app.tfstate"
    profile = "hca"
    bucket = "org-humancellatlas-861229788715-terraform"
  }
}

////
// general setup
//

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
            "Action": [
                "xray:PutTraceSegments",
                "xray:PutTelemetryRecords"
            ],
            "Resource": "*"
        },
        {
          "Effect": "Allow",
          "Action": [
            "s3:ListAllMyBuckets",
            "s3:HeadBucket"
          ],
          "Resource": "*"
        },
        {
          "Effect": "Allow",
          "Action": [
            "s3:ListBucket"
          ],
          "Resource": "arn:aws:s3:::logs-test-861229788715"
        },
        {
          "Effect": "Allow",
          "Action": ["s3:GetObject", "s3:PutObject"],
          "Resource": [
            "arn:aws:s3:::logs-test-861229788715/*"
          ]
        }
    ]
}
EOF
  depends_on = [
    "aws_iam_role.x_ray_profiling_experiment"
  ]
}

////
// build
//

data "archive_file" "lambda_zip" {
  type = "zip"
  source_dir = "./target"
  output_path = "./lambda.zip"
}

resource "aws_lambda_function" "x_ray_profiling_experiment" {
  function_name = "x-ray-profiling-experiment"
  description = "X-Ray profiling experiment"
  filename = "${data.archive_file.lambda_zip.output_path}"
  role = "${aws_iam_role.x_ray_profiling_experiment.arn}"
  handler = "app.app"
  runtime = "python3.6"
  memory_size = 256
  timeout = 120
  source_code_hash = "${base64sha256(file("${data.archive_file.lambda_zip.output_path}"))}"
  tracing_config {
    mode = "Active"
  }
  depends_on = [
    "data.archive_file.lambda_zip"
  ]
}

////
// ApiGateway
//

resource "aws_api_gateway_rest_api" "x_ray_profiling_experiment" {
  name        = "x-ray-profiling-experiment"
  description = "X-Ray profiling experiment"
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = "${aws_api_gateway_rest_api.x_ray_profiling_experiment.id}"
  parent_id   = "${aws_api_gateway_rest_api.x_ray_profiling_experiment.root_resource_id}"
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = "${aws_api_gateway_rest_api.x_ray_profiling_experiment.id}"
  resource_id   = "${aws_api_gateway_resource.proxy.id}"
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id = "${aws_api_gateway_rest_api.x_ray_profiling_experiment.id}"
  resource_id = "${aws_api_gateway_method.proxy.resource_id}"
  http_method = "${aws_api_gateway_method.proxy.http_method}"

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "${aws_lambda_function.x_ray_profiling_experiment.invoke_arn}"
}

resource "aws_api_gateway_method" "proxy_root" {
  rest_api_id   = "${aws_api_gateway_rest_api.x_ray_profiling_experiment.id}"
  resource_id   = "${aws_api_gateway_rest_api.x_ray_profiling_experiment.root_resource_id}"
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_root" {
  rest_api_id = "${aws_api_gateway_rest_api.x_ray_profiling_experiment.id}"
  resource_id = "${aws_api_gateway_method.proxy_root.resource_id}"
  http_method = "${aws_api_gateway_method.proxy_root.http_method}"

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "${aws_lambda_function.x_ray_profiling_experiment.invoke_arn}"
}

resource "aws_api_gateway_deployment" "x_ray_profiling_experiment" {
  depends_on = [
    "aws_api_gateway_integration.lambda",
    "aws_api_gateway_integration.lambda_root",
  ]

  rest_api_id = "${aws_api_gateway_rest_api.x_ray_profiling_experiment.id}"
  stage_name  = "test"
}

////
// permissions
//

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.x_ray_profiling_experiment.arn}"
  principal     = "apigateway.amazonaws.com"

  # The /*/* portion grants access from any method on any resource
  # within the API Gateway "REST API".
  source_arn = "${aws_api_gateway_deployment.x_ray_profiling_experiment.execution_arn}/*/*"
}

output "base_url" {
  value = "${aws_api_gateway_deployment.x_ray_profiling_experiment.invoke_url}"
}