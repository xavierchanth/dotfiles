---
name: documentation-system
description: Design, create, migrate, or audit a repository-wide documentation system organized by reader need and semantic authority. Use for greenfield setup or broad brownfield reorganization, not isolated documentation edits.
---

Organize documentation by reader need and semantic authority, not by the incidental source tree.

Match the work to the request:

- Audit — report structural, authority, navigation, and accuracy problems.
- Design — propose the documentation tree and authority model.
- Create or migrate — implement an approved structure and preserve valid existing knowledge.

Start with discovery:

- Read repository instructions, the root README, existing documentation, roadmaps, build configuration, and relevant source and tests.
- Inventory first-party Markdown.
- Verify important documentation claims against source, tests, and configuration.
- Determine whether the repository is greenfield or brownfield and whether it contains one documentation project or several.
- Do not choose a layout before completing discovery.

Read references only when needed:

- Always read [the system model](references/system-model.md).
- Read [selectable layouts](references/layouts.md) when designing the documentation tree.
- Read [the brownfield workflow](references/brownfield.md) when documentation is scattered, conflicting, or being migrated.
- Read [document roles and style](references/document-roles.md) when creating or auditing pages.

Ask only unresolved questions whose answers would materially change the layout, authority model, migration, or validation approach.

Before a broad reorganization, present the proposed tree, authority precedence, canonical concept owners, migration dispositions, and omitted roles for approval.

When building or revising the system:

- Create only documentation roles with meaningful content.
- Give each multi-page area an index with annotated links.
- Give each page one H1 and an opening statement of purpose and scope.
- Define each stable concept once and link to its authority.
- Separate intended design, released behavior, repository engineering, and delivery state.
- Preserve and update incoming relative links.
- Adapt `assets/check-docs.mjs` when repository-local documentation validation is warranted.

Validate headings, local links, index reachability, canonical ownership, and repository-provided documentation checks. Report what changed, what was deferred or retired, and any unresolved ownership.
