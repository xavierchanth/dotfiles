# Verify the result

Choose checks that establish intended behavior and important contracts for the current revision. Use repository-provided development tooling and relevant existing checks.

Combine focused tests, static inspection, builds or runtime exercises according to the change. Review available verification reports for their scope and revision; reuse valid evidence and refresh what changed.

Assume the project supports local development from the checkout and its declared tooling without external secrets or environment files. Do not copy .env files from the main checkout. If that assumption fails, continue useful static review and report the specific blocked runtime checks.

Record commands or steps, results, revision, and material environment limits. Distinguish local results, remote CI, and instructions not yet executed. Run required checks and avoid repeating passing checks without a new reason.

Return what the evidence establishes and what remains unknown.
