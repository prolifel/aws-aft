output "state_bucket_name" {
  description = "Name of the state bucket. Paste it into the backend blocks of the other roots."
  value       = aws_s3_bucket.state.id
}
