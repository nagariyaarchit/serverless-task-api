provider "aws" {
    region = var.region
}

# Create the DynamoDB table
resource "aws_dynamodb_table" "tasks" {
  name         = "Tasks-dev"
  billing_mode = var.billing_mode 

  hash_key = "taskId"

  attribute {
    name = "taskId"
    type = "S"
  }

  ttl {
    attribute_name = "expireAt" 
    enabled        = true
  }

  table_class = "STANDARD"

  tags = {
    Name        = "tasks-table-dev"
    Environment = "dev"
    Project     = "serverless-task-api"
  }
}

# Create the role for the lambda function
resource "aws_iam_role" "lambda_role" {
  name = "lambda_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

# Create a appropriate policy to assign to role for the lambda function 
data "aws_iam_policy_document" "dynamodb_access" {
  statement {
    actions = [
      "dynamodb:GetItem", 
      "dynamodb:PutItem", 
      "dynamodb:UpdateItem", 
      "dynamodb:DeleteItem",
      "dynamodb:Scan",
      ]
    resources = [aws_dynamodb_table.tasks.arn]
  }
}

# Convert the custom policy created to a name policy that we can use
resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name   = "lambda-dynamodb-policy"
  policy = data.aws_iam_policy_document.dynamodb_access.json
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

# Give it cloudwatch logs permission
resource "aws_iam_role_policy_attachment" "lambda_basic_exec" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# define the lambda function's source directory and an output path where terraform 
#   creates a zip for the source directory
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = var.output_path
}

# Create the lambda function with the environment
resource "aws_lambda_function" "py" {
  filename      =  data.archive_file.lambda_zip.output_path
  source_code_hash = filebase64sha256( data.archive_file.lambda_zip.output_path)
  function_name = "mylambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.handler"
  runtime       = "python3.12"

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.tasks.name
    }
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name = "myapi"
}

# /tasks
resource "aws_api_gateway_resource" "tasks" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "tasks"
}

# /tasks/{taskId}
resource "aws_api_gateway_resource" "task" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.tasks.id
  path_part   = "{taskId}"
}

# GET /tasks
resource "aws_api_gateway_method" "tasks_get" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.tasks.id
  http_method   = "GET"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "tasks_get" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.tasks.id
  http_method             = aws_api_gateway_method.tasks_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.py.invoke_arn
}

# GET /tasks/{taskId}
resource "aws_api_gateway_method" "task_get" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.task.id
  http_method   = "GET"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "task_get" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.task.id
  http_method             = aws_api_gateway_method.task_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.py.invoke_arn
}

# PUT /tasks/{taskId}
resource "aws_api_gateway_method" "task_put" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.task.id
  http_method   = "PUT"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "task_put" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.task.id
  http_method             = aws_api_gateway_method.task_put.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.py.invoke_arn
}

# DELETE /tasks/{taskId}
resource "aws_api_gateway_method" "task_delete" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.task.id
  http_method   = "DELETE"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "task_delete" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.task.id
  http_method             = aws_api_gateway_method.task_delete.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.py.invoke_arn
}

# giving Lambda permissions
resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.py.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*/*"
}

# Ensure a fresh deployment when API pieces change
resource "aws_api_gateway_deployment" "current" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.tasks.id,
      aws_api_gateway_resource.task.id,

      aws_api_gateway_method.tasks_get.id,
      aws_api_gateway_integration.tasks_get.id,

      aws_api_gateway_method.task_get.id,
      aws_api_gateway_integration.task_get.id,

      aws_api_gateway_method.task_put.id,
      aws_api_gateway_integration.task_put.id,

      aws_api_gateway_method.task_delete.id,
      aws_api_gateway_integration.task_delete.id
    ]))
  }

  depends_on = [
    aws_api_gateway_integration.tasks_get,
    aws_api_gateway_integration.task_get,
    aws_api_gateway_integration.task_put,
    aws_api_gateway_integration.task_delete,
  ]

  lifecycle { create_before_destroy = true }
}


resource "aws_api_gateway_stage" "dev" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.current.id
  stage_name    = "dev"
}
