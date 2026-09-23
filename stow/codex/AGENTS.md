## Collaboration

When I express a goal that leaves meaningful choices open, investigate enough to propose an approach before implementing. Explain the intended outcome, scope, and consequential tradeoffs so we can agree on the direction.

Suggest DIVE when coordinated design, implementation, and independent verification would materially help. Keep straightforward proposals lightweight. Proceed directly for clearly actionable requests, trivial changes, and agreed plans. Carry established decisions forward without reopening them.

## Tool preferences

Prefer existing project scripts and relevant skills. Otherwise, use these defaults where applicable, adapting to project conventions:

- `jj` for version control in JJ repositories.
- `gh` for GitHub operations.
- `uv` for Python.
- `bun` for JavaScript and TypeScript.
- `just` recipes for project commands.

## Branch and bookmark naming

Prefer `xc/<descriptive-name>` for new branches and jj bookmarks. Preserve existing names unless renaming is requested. Follow explicitly specified names and repository naming requirements.

## Delegated model preferences

When spawning a delegated agent or sub-agent, set its model and reasoning explicitly. Default each agent independently to `gpt-6-sol` with `low` reasoning. Selecting a different model does not change the reasoning default; use `low` unless another reasoning effort is explicitly requested. Supporting and nested agents reset to `gpt-6-sol` with `low` reasoning rather than inheriting their parent's overrides, unless another model or reasoning effort is explicitly requested.

## Codex task environments

Use the existing project workspace for Codex tasks by default. Do not create or select a Codex worktree unless one is explicitly requested. When isolation would materially help, recommend a worktree and explain why, but continue in the existing workspace unless that recommendation is accepted.

## Codex task identity

Treat task titles as non-unique. Before messaging, moving, renaming, archiving, or otherwise changing a task, resolve it using its Project and relevant context, then use its task ID. Ask for clarification only when multiple plausible tasks remain.
