# Brownfield migration

## Inventory and classify

Inventory first-party documents and classify each page or coherent section as:

| Class | Destination |
|---|---|
| Intended product/system design | Product, architecture, specification, or protocol |
| Exact stable contract or lookup data | Reference |
| Task-oriented integration instructions | Developer guides |
| Current implementation inventory or engineering convention | `repo/` or contributor guidance |
| Delivery gaps, sequencing, temporary compatibility | Roadmap |
| Enduring historical decision | Incorporate into its semantic authority |
| Immutable historical evidence | Clearly labeled evidence/archive, if retention has value |
| Duplicate, stale, or conflicting prose | Retire after active decisions and links are accounted for |

Record uncertain classifications rather than silently choosing.

## Establish an authority map

Before moving files, identify:

- the canonical owner of every major concept, state machine, schema, and status;
- precedence between architecture, specifications, protocols, references, and source/tests;
- project boundaries and shared concerns;
- current documents that conflict with the proposed authority;
- decisions that exist only in historical material;
- incoming links and public paths that may require compatibility consideration.

Present this map and target tree for approval before broad changes.

## Migrate in safe increments

1. Create top-level and project indexes.
2. Establish style and authority rules.
3. Move or rewrite canonical design by subject.
4. Extract delivery state and gaps into the roadmap.
5. Separate repository engineering from product/system design.
6. Add developer reading paths and references only where needed.
7. Update incoming links and nearest indexes with each move.
8. Retire duplicate or conflicting pages only after preserving enduring decisions.
9. Add graph validation.
10. Recheck claims against source/tests and report remaining mismatches.

Prefer semantic increments over one opaque repository-wide rewrite. Do not combine documentation restructuring with unrelated behavior changes.

## Common failure modes

- Treating every package as a project.
- Copying the current source tree into architecture.
- Calling a future-first design “current documentation” without an authority disclaimer.
- Keeping status in architecture because it is convenient.
- Maintaining both an old and new normative tree indefinitely.
- Turning initiatives into daily logs or completed-checkpoint journals.
- Creating developer guides for APIs that do not exist.
- Preserving every old document without a reader or evidentiary purpose.
