# Documentation system model

## Separation of concerns

The system separates six kinds of truth:

| Truth | Typical authority |
|---|---|
| Product promise, users, goals, and non-goals | Product document |
| Intended boundaries, ownership, trust, and rationale | Architecture |
| Normative domain and integration behavior | Specification |
| Exchanged bytes, records, ordering, and compatibility | Protocols |
| Exact stable lookup surfaces | Reference |
| Current gaps, sequencing, and proposed outcomes | Roadmap |

Task-oriented developer guides consume these authorities without redefining them. Repository engineering documentation describes the current repository, tooling, CI, infrastructure, workspaces, and placement rules without becoming product architecture.

## Default precedence

When documents overlap, use this default and adjust it explicitly for the domain:

1. protocol documents control bytes, encoding, and cryptographic transcripts;
2. specifications control normative ownership, lifecycle, and integration behavior;
3. architecture explains boundaries and rationale;
4. reference provides stable lookup surfaces;
5. developer guides explain supported tasks without redefining contracts;
6. the roadmap alone records delivery state and gaps;
7. source and tests control exact released behavior unless versioned release specifications explicitly say otherwise.

## Core invariants

- One authoritative definition exists for each stateful or normative concept.
- Intended design and delivery tracking never share a document.
- Documentation is organized around reader need and semantic ownership, not package layout.
- Indexes form a navigable graph with annotated links.
- Current implementation inventories belong in repository documentation; implementation gaps belong in the roadmap.
- Historical narration is not an active authority.
- Version control owns timestamps and completed-work history.

## Future-first versus release-first

Use future-first docs when the repository is converging on a designed end state and can clearly state that source/tests remain authoritative for released behavior. This supports architectural coherence without pretending completion.

Use release-first or versioned docs when external consumers require documentation that exactly matches shipped versions. In that case, keep proposals and future design in clearly separate design/roadmap areas. Never silently mix target and released contracts.
