# Create an isolated review checkout

Create an independent temporary Git repository for review, reusing available local objects. Git is appropriate for this capability even when normal development uses JJ.

## Establish the source

Resolve the PR's GitHub repository and exact head/base SHAs through gh. Locate the existing repository's actual Git storage: for a Git or colocated JJ checkout use Git's repository discovery; for non-colocated JJ use the installed JJ Git-root command/help. Resolve pointers rather than assuming .git is a directory or hardcoding JJ's internal storage layout.

Read source metadata only. Do not export, snapshot, switch or otherwise mutate the original repository to prepare a review.

## Clone and select the PR

Create a unique private task directory under /tmp using mktemp, with the clone in a child directory. Record ownership and the exact path for cleanup.

Use a local-path `git clone --local --no-checkout` from the discovered Git storage. Local cloning can hard-link objects where supported and keeps refs and configuration separate. Avoid --shared and persistent alternates dependencies; if the source itself borrows objects, dissociate the new clone before relying on independence. If local cloning is unsuitable or races with concurrent source changes, fall back to a normal clone from the verified GitHub repository.

In the temporary clone only, replace the local-source origin URL with the verified GitHub repository URL. Use `gh pr checkout <PR-URL> --detach`. Fetch the required base/history and confirm the checked-out HEAD equals the recorded PR head; reconcile movement before beginning review.

Record head, base and merge-base SHAs. Use the merge-base-to-head diff for PR changes, and distinguish it from any separate integration test against the current base. Submodules or large-file content may require additional project-specific fetching; report limitations.

The checkout represents published PR commits. It does not copy uncommitted files, local .env files or the original JJ operation history.

## Clean up

Keep the review report and useful evidence outside the disposable clone. Stop task-owned development processes. Preserve valuable edits or artifacts before removal.

Remove only the task-owned temporary directory after verifying its identity. No JJ workspace registration is created, so no workspace forget operation is needed. Perform cleanup on completion and recoverable early exits; system temporary cleanup is a fallback. If interrupted, report any remaining path for later cleanup.

This isolates repository state, not execution privileges or inherited process environment.

References: [Git local cloning](https://git-scm.com/docs/git-clone), [gh PR checkout](https://cli.github.com/manual/gh_pr_checkout).
