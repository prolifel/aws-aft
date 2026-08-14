module "aft-sandbox" {
  source = "./modules/aft-account-request"

  control_tower_parameters = {
    AccountEmail = "cclement.085w+test1@gmail.com"
    AccountName  = "sandbox-account-01"
    # Syntax for top-level OU
    ManagedOrganizationalUnit = "Sandbox"
    # Syntax for nested OU
    # ManagedOrganizationalUnit = "Sandbox (ou-xfe5-a8hb8ml8)"
    SSOUserEmail     = "cclement.085w+test1@gmail.com"
    SSOUserFirstName = "sandbox"
    SSOUserLastName  = "test1"
  }

  account_tags = {
    "AFT:Owner"       = "cclement.085w+test1@gmail.com"
    "AFT:Division"    = "ENT"
    "AFT:Environment" = "Dev"
    "AFT:CostCenter"  = "123456"
    "AFT:Vended"      = "true"
    "AFT:DivCode"     = "102"
    "AFT:BUCode"      = "AFT003"
    "AFT:Project"     = "123456"
  }

  change_management_parameters = {
    change_requested_by = "clement"
    change_reason       = "testing the account vending process"
  }

  account_customizations_name = "sandbox-account-01-customizations"

}
