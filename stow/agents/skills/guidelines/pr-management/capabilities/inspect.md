# Inspect PR context

Return a grounded snapshot: host/repository, PR URL and number, base/head refs and SHAs, purpose, relevant instructions, changed surfaces, checks, feedback and uncertainties.

Use `gh pr view`, `gh pr diff`, `gh pr checks`, `gh run view` and `gh api` as needed. Use structured JSON fields and explicit repository targets. Check installed command help for supported fields and options. Paginate API collections so feedback and files are not silently omitted.

For an existing PR, read its body, linked context, published reviews, issue comments and inline review threads. `gh pr view --comments` alone is not a complete inventory of inline review threads; use the API when needed. Distinguish pending reviews, resolved threads and unresolved follow-ups.

For preparation before a PR exists, establish the intended base and complete branch diff. Use available decisions, plans and test reports without requiring a particular upstream skill.

Read repository contribution rules and templates. Confirm fork head repository separately from the base repository. Note if the remote head changes during inspection.
