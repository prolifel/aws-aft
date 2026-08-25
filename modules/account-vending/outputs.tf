locals {
  account_id_outputs = {
    for o in aws_servicecatalog_provisioned_product.this.outputs : o.key => o.value
  }
}

output "provisioned_account_id" {
  description = "AWS account ID of the provisioned account."
  value       = local.account_id_outputs["AccountId"]
}
