# Diagnose checks

Identify the failed run, job and head SHA before acting. Inspect available failed-job logs promptly; a whole-run summary may remain pending while a job has already failed.

Use `gh run view <run-id> --log-failed` and structured job information. If needed, use GitHub's Actions jobs API for individual job logs. Confirm repository and run identity.

Classify from evidence:
- Branch defect: logs and code connect the failure to the proposed changes. Fix the cause.
- Transient or external failure: evidence points to infrastructure, provisioning, network or external-service trouble. Consider a bounded retry.
- Unresolved: investigate the missing link before choosing either.

A timeout alone does not establish flakiness; changed code may cause it. Avoid unrelated test or infrastructure changes merely to make checks green.

Default to at most three retry cycles for the same failure on the same head, carrying the count across monitoring runs. Stop earlier when retries cannot help; a new run ID does not reset the budget. Return classification, evidence, affected revision, proposed action and remaining uncertainty.
