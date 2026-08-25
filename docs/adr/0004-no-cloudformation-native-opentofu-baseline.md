# No CloudFormation; native OpenTofu baseline

The legacy per-account baseline shipped as a CloudFormation template using Lambda-backed custom resources. It is re-implemented entirely with native OpenTofu resources (IAM password policy, alternate contacts, roles/policies, KMS, Glue encryption, S3/EBS account settings); no CloudFormation template remains. The Lambda custom resources existed only to bridge CloudFormation gaps that OpenTofu covers natively.
