# Repo scope: vending only

This repo is reconstructed as a Control Tower account-vending repo only. GuardDuty, Inspector, Macie, Security Hub, and the hardening/SCP/encryption/detection control families move to a separate repo. The split exists because account vending and security enablement have different ownership and release cadence, and keeping them together made every vending change drag security configuration along.
