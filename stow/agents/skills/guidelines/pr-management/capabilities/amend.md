# Amend the branch

Make corrections within the authorized maintenance scope. Establish the PR head repository, branch and expected remote SHA, and inspect local state before editing.

Use JJ when the working repository uses it, following the user's version-control conventions. Use Git where required by the isolated review clone workflow. Keep unrelated local edits intact; use isolation when they overlap rather than changing the main checkout.

Group changes by coherent outcome, keeping supporting tests and documentation together. Verify before the authorized commit/push. Use Conventional Commit messages describing the correction.

Refresh the remote head before pushing; if someone has advanced it, reconcile their changes without overwriting them. Do not force-push as a routine correction. When authorized maintenance in a JJ repository intentionally rewrites commits, that authorization includes pushing the corresponding moved bookmarks with JJ. Verify the exact bookmark destinations and remote divergence first, and keep unrelated bookmark moves outside the push. Confirm the pushed commit IDs and destinations afterward.

Return changed behavior, commit IDs, checks and unresolved concerns. If valuable edits were made in a temporary clone, persist them through the authorized destination or preserve a recoverable artifact before cleanup.
