# Account vending and bootstrap as OpenTofu modules

Vending is modeled as an OpenTofu root per account that provisions Control Tower Account Factory through Service Catalog (`modules/account-vending`), and bootstrap applies the mandatory baseline with native OpenTofu resources (`modules/account-bootstrap`). Each account vending operation is an OpenTofu state transition, persisted in central S3 with per-account keys, instead of AFT's framework state.
