# Account identity is immutable; deletion archives

Email, account name, and initial OU are immutable once an account is vended, and OU moves require a dedicated operation. Removing an account request archives it without deleting the AWS account, and reruns reconcile bootstrap items only without re-vending. These rules exist because an AWS account, once created, cannot be renamed or safely destroyed.
