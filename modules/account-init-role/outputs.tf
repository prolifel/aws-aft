output "role_name" {
  description = "Name of the per-account deploy role."
  value       = aws_iam_role.this.name
}

output "role_arn" {
  description = "ARN of the per-account deploy role."
  value       = aws_iam_role.this.arn
}
