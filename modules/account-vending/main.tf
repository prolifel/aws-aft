data "aws_servicecatalog_product" "account_factory" {
  id = var.account_factory_product_id
}
data "aws_servicecatalog_provisioning_artifacts" "account_factory" {
  product_id = data.aws_servicecatalog_product.account_factory.id
}
locals {
  artifacts = {
    for p in data.aws_servicecatalog_provisioning_artifacts.account_factory.provisioning_artifact_details : p.name => p
  }
  active_artifacts = {
    for name, p in local.artifacts : name => p if p.active
  }
  artifact_ids = values(local.active_artifacts)
  artifact_id  = try(local.artifact_ids[0].id, "")
}
# DUPLICATE handling: a Service Catalog provisioned product is keyed by its
# name, so re-applying the same account_name reconciles the existing product
# rather than creating a duplicate account. Idempotency intent is preserved by
# keeping the identity fields (name, email, OU) stable on the resource.
resource "aws_servicecatalog_provisioned_product" "this" {
  name                     = "account-${var.account_name}"
  product_id               = data.aws_servicecatalog_product.account_factory.id
  provisioning_artifact_id = local.artifact_id
  provisioning_parameters {
    key   = "AccountName"
    value = var.account_name
  }
  provisioning_parameters {
    key   = "AccountEmail"
    value = var.email
  }
  provisioning_parameters {
    key   = "ManagedOrgUnit"
    value = var.managed_org_unit
  }
  # SSO parameters are optional: only emitted when the value is non-empty so a
  # minimal request can skip SSO user creation entirely.
  dynamic "provisioning_parameters" {
    for_each = var.sso_user_email != "" && var.sso_user_email != null ? [1] : []
    content {
      key   = "SSOUserEmail"
      value = var.sso_user_email
    }
  }
  dynamic "provisioning_parameters" {
    for_each = var.sso_user_first_name != "" && var.sso_user_first_name != null ? [1] : []
    content {
      key   = "SSOUserFirstName"
      value = var.sso_user_first_name
    }
  }
  dynamic "provisioning_parameters" {
    for_each = var.sso_user_last_name != "" && var.sso_user_last_name != null ? [1] : []
    content {
      key   = "SSOUserLastName"
      value = var.sso_user_last_name
    }
  }
  tags = var.account_tags
}
