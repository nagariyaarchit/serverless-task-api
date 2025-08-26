variable "region" {
    description = "Region where the compute resources are going to be launched"
}

variable "billing_mode" {
    description = "billing mode for DynamoDB table"
}

variable "source_dir" {
    description = "Local directory containing the Lambda function's source code"
}

variable "output_path" {
    description = "Local directory where terraform zip's the lambda function's source code"
}

variable "accountID" {
    description = "Aws console account ID"
}