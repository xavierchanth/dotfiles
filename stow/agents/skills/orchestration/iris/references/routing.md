# Vocabulary, Projects, and workspaces

Read private configuration through `~/.agents/config/iris/`. Home Manager links this directory to the Dotfiles checkout's ignored `local/iris/`, independently of the Stow-managed skill tree. Update the files through that overlay; the private data survives skill updates. When the overlay is absent, use conversation and live harness evidence and report the missing setup when persistence is needed.

`vocabulary.yaml` stores recognition aliases. `workspaces.yaml` stores organizations, filesystem workspaces, and semantic Projects that reference those workspaces. Live harness state remains authoritative for saved Projects, Teams, task identities, access, and execution. Configuration helps interpret that state; it does not grant access or create saved Projects.

## Vocabulary

Use `version: 1` and optional `organizations`, `workspaces`, `projects`, and `terms` mappings. Each canonical key maps to a list of aliases:

```yaml
version: 1
organizations:
  example: [Example Org]
workspaces:
  example/tool: [Example Tool]
projects:
  example/integration: [Integration, Tool Integration]
terms:
  example-term: [Example Term, Spoken Variant]
```

Organization, workspace, and Project keys refer to the corresponding records in `workspaces.yaml`. Terms normalize language independently of any workspace or Project and do not trigger routing. Use Project aliases when recognition depends on the semantic context; use workspace aliases for a repository or folder itself. If an alias has multiple plausible meanings, retain that ambiguity and resolve it from context instead of choosing an arbitrary target.

## Organizations, workspaces, and Projects

Use `version: 1` with optional `organizations`, `workspaces`, and `projects` mappings:

```yaml
version: 1
organizations:
  example:
    name: Example Org
    root: /path/to/organization
    github_owners: [example-owner]
workspaces:
  example/config:
    name: Configuration
    organization: example
    primary_path: /path/to/config-repository
    repository: config
    github_owner: example-owner
  example/tool:
    name: Example Tool
    organization: example
    primary_path: /path/to/tool-repository
projects:
  example/config:
    name: Configuration
    primary_workspace: example/config
    project_labels: [Configuration]
    purpose: Maintain machine configuration.
  example/integration:
    name: Integration
    primary_workspace: example/config
    additional_workspaces: [example/tool]
    project_labels: [Integration]
    purpose: Integrate the tool with machine configuration.
```

Organizations require `name` and `root`. Workspaces require `name` and `primary_path`; organization, repository metadata, and folder purpose are optional. A workspace identifies a repository or ordinary folder on disk. Projects require `name` and `primary_workspace`; organization, purpose, stable saved-Project labels, and additional workspace keys are optional. All references must resolve within their respective mappings.

Multiple Projects may share a primary workspace while having different purposes and additional workspaces. Additional workspaces describe the Project's intended scope, not implicit saved Projects or access permissions. Keep task IDs, priorities, and transient execution status in live coordination state rather than these files.

## Resolution and updates

Normalize vocabulary first, then combine Project purpose, workspace paths, configured labels, conversation context, and live harness evidence. A shared path alone cannot distinguish semantic Projects. Treat configured labels as durable hints and obtain current names and IDs from the harness. Route work to the Project whose purpose fits, using the relevant workspace as its working scope.

When Xavier explicitly establishes an unambiguous durable mapping, persist it without redundant confirmation and report the update naturally. Preserve unrelated entries and check alias collisions, duplicate keys, and unresolved references before writing. Shared paths between Projects are intentional when their purposes differ. When durability or target is inferred or ambiguous, propose the mapping or ask one concise question.
