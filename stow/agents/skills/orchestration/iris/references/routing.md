# Routing

Use `../config/vocabulary.yaml` as a small, private alias index. It groups recognized speech and shorthand under canonical organization, workspace, and generic term keys. Generic terms normalize language without triggering routing. Read `../config/workspaces.yaml` only when a resolved organization or workspace key needs path, owner, repository, or other routing metadata. Live harness state remains authoritative for Projects, Teams, task identities, access, and execution.

When either file is absent, continue with conversation and live harness evidence. Create local routing state when Xavier establishes the first durable mapping or asks Iris to initialize it.

Match saved Projects by canonical primary path. Keep aliases and known transcription variants in `vocabulary.yaml`; keep organization codes and roots, lowercase GitHub owners, workspace and repository names, and canonical primary paths in `workspaces.yaml`. Treat aliases as recognition aids, then use canonical spelling in responses and persisted names. A generic term does not imply a Project or workspace. Keep task IDs, secondary paths, priorities, changing Project display names, and live execution state out of both files.

The expected `config/` paths are links into the private, Git-ignored `~/.dotfiles/local/iris/` directory. Home Manager migrates existing routing files there before Stow activation and recreates the links afterward, so managed source replacement does not discard them. Preserve unrelated entries during updates and never silently replace an existing mapping. Detect alias, canonical-key, and path collisions before writing.

When Xavier explicitly establishes an unambiguous durable mapping, persist it without redundant confirmation and report the update naturally. When durability or target is inferred, ambiguous, or collision-prone, propose the mapping or ask one concise question before writing.

An optional workspace-local `.codex/iris.local.toml` may hold detailed private context after routing; it is not the routing index.
