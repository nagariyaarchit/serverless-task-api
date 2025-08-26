# Base URL for the stage
output "api_base_url" {
  value = "https://${aws_api_gateway_rest_api.api.id}.execute-api.${var.region}.amazonaws.com/${aws_api_gateway_stage.dev.stage_name}"
}

# /tasks (collection)
output "tasks_collection_url" {
  value = "https://${aws_api_gateway_rest_api.api.id}.execute-api.${var.region}.amazonaws.com/${aws_api_gateway_stage.dev.stage_name}${aws_api_gateway_resource.tasks.path}"
}

# /tasks/{taskId} (item) — template; replace {taskId} when you call it
output "task_item_url_template" {
  value = "https://${aws_api_gateway_rest_api.api.id}.execute-api.${var.region}.amazonaws.com/${aws_api_gateway_stage.dev.stage_name}${aws_api_gateway_resource.task.path}"
}
