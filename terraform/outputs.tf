output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "lambda_function_arn" {
  value = aws_lambda_function.wind_alarm.arn
}
