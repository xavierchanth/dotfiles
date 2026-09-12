# Manage native GitHub stacked PRs

Use this workflow for native GitHub stacked pull requests. A native stack is a linear sequence of PRs in one repository whose membership is recorded by GitHub's stack commands. GitHub requires linear history to merge a stack.

Start with [Inspect](../capabilities/inspect.md). Map each coherent change layer to its commits, branch, PR URL, base, head, draft state, checks and stack position. Preserve existing PR identities, human-authored context and draft state. Follow repository or user naming conventions; do not introduce a personal branch prefix.

Choose the path that matches the requested outcome:

1. **Inspect or map.** Read current remote and PR state, then show the linear layer order and any mismatch between history, PR bases, per-layer diffs and native stack membership. Keep this path read-only unless the request includes changes.
2. **Create or adopt.** Shape and publish a linear series. Resolve existing PRs for every layer first, reuse their identities and content, and create only missing PRs with [Describe](../capabilities/describe.md) and [GitHub actions](../capabilities/github-actions.md). Link the full ordered list of explicit PR URLs from bottom to top.
3. **Extend.** Native linking supports adding a layer only at the top. Publish the new top layer, resolve or create its PR, then pass the full ordered list of existing and new explicit PR URLs from bottom to top to `gh stack link`.
4. **Update.** Amend or restack with the repository's version-control workflow, verify, and publish every affected layer using [Amend](../capabilities/amend.md). Refresh every affected PR and stack relationship afterward. Linking is additive; for arbitrary reordering, insertion between members, or removal, produce a concrete plan and state the native CLI limitation rather than improvising mutations.
5. **Advance after merges.** GitHub may rebase commits or retarget dependent PRs when a stack member merges. Refresh and reconcile remote history before the next restack or publication. Identify landed changes and avoid replaying them.
6. **Recover.** After any partial or ambiguous failure, read back published branches, PRs and native membership before retrying. Resume only missing operations so retries do not duplicate PRs or links.

After publishing, restacking, or allowing `gh stack link` to correct bases, verify each layer's base, head and diff against its intended change. Associate checks with the resulting revisions.

## JJ repositories

Load `jj-guidelines`. JJ owns local history, bookmarks, fetches, restacking and pushes; avoid GitHub stack commands that manage local tracking. Use `gh pr` for PR creation and metadata. Use `gh stack link` with explicit PR URLs only after JJ has pushed the intended bookmarks and `gh pr` has deliberately created any missing PRs. Branch arguments to `gh stack link` push automatically, which bypasses this ownership boundary.

When a layer changes, identify every affected descendant bookmark. Verify and push all of them with JJ before linking or updating GitHub metadata, then perform the per-layer base, head and diff verification above.

## Merge scope and completion

Selecting a higher PR for merge includes every unmerged prerequisite below it. Merge only when the authorized scope includes all of those PRs; otherwise report the required merge set. Use GitHub's native stack merge operation when available, then read back every affected PR.

If the stack extension or feature is unavailable, report that limitation. Do not present an ordinary chain of dependent PRs as a native GitHub stack.

Consult GitHub's official references when command behavior may have changed: [stacked PR CLI commands](https://docs.github.com/en/pull-requests/reference/stacked-prs-cli-commands), [using other tools](https://docs.github.com/en/pull-requests/reference/use-other-tools-with-stacked-pull-requests), [stacked pull requests](https://docs.github.com/en/pull-requests/reference/stacked-pull-requests), and [merging stacked pull requests](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/merging-stacked-pull-requests).

Completion requires the requested history and PR state, explicit readback of native membership, and current checks for the revisions they cover.
