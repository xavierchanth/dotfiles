# Update GitHub

Use `gh` for the requested remote action. Confirm repository, PR, current head and relevant state immediately beforehand.

Typical actions use `gh pr create`, `gh pr edit`, `gh run rerun <run-id> --failed`, `gh pr comment`, `gh pr review`, or `gh api` for review threads. Check command help or official API documentation when parameters are uncertain.

Prepare exact text before publishing. For multiline content, use a structured argument or a temporary body file with `--body-file`; avoid shell interpolation of prose. Preserve useful human-authored content when updating descriptions.

Read authorization from the user's request and established session scope. Observation does not authorize code pushes, comments, approvals, thread resolution or merging. An authorized PR create/edit request permits its body update. Post messages to others only when explicitly authorized; otherwise return a suggested response. Resolve a thread only when authorized and its concern is addressed.

After writing, read back the resulting content/state. If a write times out or returns an ambiguous result, inspect remote state before retrying to avoid duplicate PRs, comments or reruns.

Return the action, target, resulting URL/state and any remaining uncertainty.
