# Repair PR checks

Establish why checks fail and restore the intended behavior within the requested scope.

1. [Inspect](../capabilities/inspect.md) runs for the current PR head.
2. [Diagnose](../capabilities/diagnose-checks.md) failed jobs from their logs before choosing a fix or retry.
3. For a branch defect, [amend](../capabilities/amend.md) the cause and [verify](../capabilities/verify.md). For a supported transient failure, use an authorized bounded retry through [GitHub actions](../capabilities/github-actions.md).
4. Inspect the resulting checks for the updated head or rerun. Avoid retrying an old revision when a corrective push will replace it.

Finish when relevant checks pass or a concrete blocker prevents further progress. Report root cause, changes or retries, evidence and remaining limits. Return state to a calling babysit workflow so monitoring resumes.
