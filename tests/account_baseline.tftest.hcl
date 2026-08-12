mock_provider "aws" {}

run "plan_smoke" {
  command = plan
}
