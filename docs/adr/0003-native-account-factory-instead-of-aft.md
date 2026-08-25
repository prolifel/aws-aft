# Replace AFT with native Control Tower Account Factory

Account requests drive Control Tower Account Factory through Service Catalog rather than the AFT framework's Step Functions and Lambda machinery. AFT's heavy custom framework was the thing being replaced; vending only needs validated requests, idempotent submission, and status polling.
