---
name: jj-guidelines
description: Use when performing version-control work, including status inspection, diffs, checkpoints, commit descriptions, stack cleanup, splitting, squashing, rebasing mutable stacks, workspace management, or deciding whether jj or git commands are appropriate.
---

# JJ Guidelines

Use these guidelines only when version-control work is needed and the repository has a `.jj` directory.

If there is no `.jj` directory, do not use these guidelines; use the repository's normal VCS workflow instead.

Keep in-progress work reviewable, recoverable, and semantically named. Prefer jj over git whenever a .jj directory is present. Use git only for repositories that are not jj repositories or when the user explicitly asks for git-specific work.

Core responsibilities:
- Create semantic checkpoints with jj new, jj commit, or jj describe when the user explicitly asks for checkpoint work or grants checkpointing permission for a larger task.
- Inspect mutable jj stacks and decide whether revisions should be described, split, squashed, rebased, or left alone.
- Clean up history into reviewable semantic units: prerequisite refactor, behavior change, tests, docs, tooling or ci, and polish.
- Enforce Conventional Commit messages with concise imperative summaries.
- Audit for generated caches, machine-local paths, secrets, build outputs, accidental lockfiles, .DS_Store files, __pycache__ directories, and other files that likely should not be committed.

Default safety model:
- Stay read-only unless the user explicitly asks for mutating VCS commands to be executed.
- Mutating commands include jj new, jj commit, jj describe, jj split, jj squash, jj rebase, jj abandon, jj file untrack, jj workspace add, jj workspace forget, jj workspace rename, git add, git commit, git rebase, git reset, and git checkout.
- For cleanup requests, return the exact command plan first and wait for confirmation unless the user explicitly asks for it to be run.
- For long-running implementation tasks where the user grants checkpointing permission, create natural checkpoints as work reaches stable milestones.
- Never use destructive commands such as git reset --hard or broad abandon operations unless the user explicitly requests that exact action and scope.

Workspace policy:
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
- Create a checkpoint when the current work has reached a coherent, buildable or reviewable milestone.
- Do not create or keep empty described commits in history; skip empty commit-style checkpoints and never describe an empty revision just to record progress.
- After completing a coherent checkpoint, prefer leaving @ on a fresh empty unnamed commit so the working copy is clean and future edits land in the right place.
- Prefer describing the current revision when it already contains exactly one coherent change.
- Prefer jj new after a coherent checkpoint, especially when more unrelated work remains.
- Prefer jj commit only when the user specifically wants a closed commit-style checkpoint.
- Avoid checkpointing pure formatting, generated output, dependency churn, or incidental cleanup together with behavior changes unless that is the coherent task.

Split and squash policy:
- Suggest jj split only when a revision spans multiple semantic buckets that would be easier to review separately.
- Do not split a small coherent revision just because multiple files changed.
- Prefer file-based jj split when buckets map cleanly to whole files.
- Prefer jj split --interactive when one file mixes multiple semantic buckets.
- Suggest jj squash when adjacent revisions are artificial fragments of the same semantic change.
- Preserve prerequisite ordering: refactor or plumbing first, then behavior, then tests, docs, tooling, or polish.

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
