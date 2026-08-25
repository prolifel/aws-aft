variable "region" {
  description = "AWS region for management-plane resources."
  type        = string
  default     = "ap-southeast-3"
}

variable "name_prefix" {
  description = "Prefix for management-plane resource names."
  type        = string
  default     = "prod"
}

variable "gitlab_url" {
  description = "GitLab OIDC issuer base URL."
  type        = string
  nullable    = false
}

variable "gitlab_project_path" {
  description = "GitLab project path allowed to assume the CI role."
  type        = string
  nullable    = false
}

variable "state_bucket_name" {
  description = "Name of the central OpenTofu state bucket."
  type        = string
  nullable    = false
}
