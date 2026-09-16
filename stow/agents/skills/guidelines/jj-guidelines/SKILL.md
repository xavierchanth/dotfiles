---
name: jj-guidelines
description: Use when performing version-control work, including status inspection, diffs, checkpoints, commit descriptions, stack cleanup, splitting, squashing, rebasing mutable stacks, workspace management, or deciding whether jj or git commands are appropriate.
---

# JJ Guidelines

Use these guidelines only when version-control work is needed and the repository has a `.jj` directory.

If there is no `.jj` directory, do not use these guidelines; use the repository's normal VCS workflow instead.

Keep in-progress work reviewable, recoverable, and semantically named. Prefer jj over git whenever a .jj directory is present. Use git only for repositories that are not jj repositories or when the user explicitly asks for git-specific work.

Core responsibilities:
- Create semantic checkpoints with jj split, jj squash, jj new, or jj describe when the user explicitly asks for checkpoint work or grants checkpointing permission for a larger task.
- Inspect mutable jj stacks and decide whether revisions should be described, split, squashed, rebased, or left alone.
- Clean up history into reviewable semantic outcomes, keeping supporting tests and documentation with the change they serve.
- Enforce Conventional Commit messages with concise imperative summaries.
- Audit for generated caches, machine-local paths, secrets, build outputs, accidental lockfiles, .DS_Store files, __pycache__ directories, and other files that likely should not be committed.

Default safety model:
- Stay read-only unless the user explicitly asks for mutating VCS commands to be executed.
- Mutating commands include jj new, jj commit, jj describe, jj split, jj squash, jj rebase, jj abandon, jj file untrack, jj workspace add, jj workspace forget, jj workspace rename, git add, git commit, git rebase, git reset, and git checkout.
- Explicit checkpoint requests grant permission for the required jj split, jj squash, jj new, and jj describe operations within the requested scope.
- For cleanup requests, return the exact command plan first and wait for confirmation unless the user explicitly asks for it to be run.
- For long-running implementation tasks where the user grants checkpointing permission, create natural checkpoints as work reaches stable milestones.
- Never use destructive commands such as git reset --hard or broad abandon operations unless the user explicitly requests that exact action and scope.

Workspace policy:
- For collaborative JJ repositories, prefer the existing shared checkout as the accumulation surface because it keeps the stream of edits available for semantic sorting. Use a separate Codex worktree or JJ workspace when independent branch lifecycles, risky experiments, conflicting dependency states, or strong filesystem isolation matter more than sharing one working-copy commit.
- When several contributors edit one shared checkout, prefer leaving implementation changes uncommitted until their intent, validation, and exact changed-file manifest are known. Coordinate checkpoint mutations so one actor changes JJ history at a time when concurrent edits or review pressure make collisions plausible.
- When checkpointing shared work, preserve the live working-copy commit and extract only confirmed changes into semantic commits beneath `@`. Leave unrelated, unfinished, or unconfirmed edits in `@`; the working copy need not become clean after each extraction.
- Jujutsu calls Git-style worktrees "workspaces"; prefer jj workspace commands over git worktree commands inside jj repositories.
- Create additional workspaces under .jj/workspaces/ with clear task-oriented directory names, e.g. jj workspace add .jj/workspaces/fix-login --name fix-login.
- Each workspace has its own working-copy commit and may have a different commit checked out; use jj workspace list or jj log to account for other workspace commits before cleanup.
- Additional workspaces point back to the initial repository storage. Do not move or delete .jj/workspaces/* directly when jj still tracks the workspace; use jj workspace forget first, then remove files only if the user asks.
- A workspace can become stale if its working-copy commit is rewritten from another workspace. Suggest jj workspace update-stale when jj reports a stale working copy.

Inspection workflow:
1. Run jj status and jj log or jj diff as needed to understand the current stack.
2. If the user names a revision or revset, inspect only that scope.
3. Otherwise inspect @ plus contiguous mutable ancestors whose descriptions are empty, start with wip:, or clearly look temporary.
4. Use jj log, jj diff --stat, jj diff -r <rev>, and changed file inspection to gather context.
5. Check for suspicious files before suggesting checkpoint or cleanup commands.

Checkpoint policy:
- Treat “checkpoint,” “checkpoint this,” and “checkpoint everything” as requests to checkpoint all pending changes in the current workspace, regardless of which task produced them.
- Narrow scope only when the user explicitly names a feature, activity, revision, or file scope. Resolve that scope from conversation and repository evidence; ask when the boundary remains ambiguous.
- A checkpoint request authorizes the necessary checkpoint mutations. Execute unless the user asks for a proposal or command plan.
- Establish the pending changes at the start of checkpointing. Leave newly arriving edits for a subsequent checkpoint.
- Group changes by coherent outcome. Keep each feature or fix with its supporting tests and documentation; separate unrelated changes and order prerequisites before their consumers.
- Prefer extracting each group into a new commit beneath @ while retaining the current working change. Leave unfinished or excluded changes in @; it need not be empty afterward.
- Use file selection when files map cleanly to outcomes. Inspect and select hunks when a file contains changes belonging to different outcomes.
- Coordinate checkpoint mutations in a shared workspace so one actor changes JJ history at a time. Settle writes to the selected files before extraction; JJ locks do not coordinate agents editing files.
- Inspect each resulting commit and the remaining diff. Check that each checkpoint contains its intended changes and prerequisites.
- Do not leave empty described checkpoints. A temporary empty destination is acceptable when immediately populated through squash.
- Report the resulting commit IDs and descriptions, plus any changes left pending and why.

Split and squash policy:
- Use jj split to extract checkpoints beneath @ or to separate a revision containing multiple unrelated outcomes.
- Do not split a small coherent revision just because multiple files changed.
- Prefer file-based jj split when buckets map cleanly to whole files.
- Prefer jj split --interactive when one file mixes multiple semantic buckets.
- Suggest jj squash when adjacent revisions are artificial fragments of the same semantic change.
- Order commits by actual dependencies. Keep supporting tests, documentation, and tooling with the outcome they serve when that produces a coherent commit.

Commit message conventions:
- Use Conventional Commits: type(optional-scope): concise imperative summary.
- Prefer types in this order when applicable: fix, feat, docs, test, refactor, perf, build, ci, style, chore.
- Derive scope from the dominant stable subsystem; omit scope for intentionally cross-cutting changes.
- Keep the summary lowercase unless it contains a proper noun.
- Do not end the summary with a period.
- Mark breaking changes with ! only when the diff clearly introduces a breaking API or behavior change.

Output rules:
- Be concise and command-oriented.
- For plan-only cleanup, include a brief diagnosis followed by exactly one fenced bash block containing the full command plan.
- Do not include shell comments inside command blocks.
- When executing commands, report what changed and any residual risks or follow-up commands.
- If no split, squash, or checkpoint is needed, say so and provide only any useful jj describe commands.
