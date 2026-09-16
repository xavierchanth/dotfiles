# Document roles and style

## Roles

- **Architecture:** components, authority, dependency direction, trust boundaries, and rationale.
- **Specification:** normative domain and integration behavior, including precedence.
- **Protocol:** exchanged records or bytes, bounds, validation, ordering, compatibility, and security-relevant failure behavior.
- **Reference:** stable lookup for APIs, states, packages, hosts, operations, and conformance requirements.
- **Developer guide:** a supported outcome, prerequisites, implementation steps, verification, and failure modes.
- **Roadmap:** current gaps, proposed outcomes, dependencies, gates, delivery state, and acceptance boundaries.
- **Index:** a reader route with annotated links, not a second authority for their content.

Choose one primary role per document.

## Page requirements

Every page has:

1. exactly one H1;
2. an opening paragraph stating purpose and scope;
3. subject-specific headings rather than mandatory empty sections;
4. relative links to authoritative definitions;
5. no manual table of contents unless length genuinely requires it.

Use sentence-case headings. Match canonical capitalization and terminology. Do not add `last updated` metadata.

## Useful shapes

### Index

```md
# Area name

Purpose, scope, and authority.

## Start here

1. [First document](first.md) — why to read it.
2. [Second document](second.md) — why to read it next.

## Subject group

- [Document](document.md) — owned subject and boundary.

## Related documentation

- [Other area](../other/README.md) — relationship to this area.
```

### Architecture or specification

Use only relevant sections: scope, model/responsibilities, authority and ownership, invariants, lifecycle/flows, failure and recovery, security/privacy, and related documentation. A specification declares normative language and precedence.

### Protocol

Cover scope, terminology, records/wire format, bounds, state/ordering, validation, failure behavior, compatibility, security, and conformance as applicable.

### Developer guide

State the outcome and support level, prerequisites, implementation/configuration steps, verification, failure modes, and next steps. Never invent an API to make target design look executable.

### Roadmap

State bounded outcomes, dependencies, gates, delivery state, and acceptance boundaries. Keep stable design in architecture, specifications, or protocols; keep execution logs and completed-work history elsewhere.

## Linking and duplication

- Annotate index links with an em dash and a reason to follow them.
- Parent indexes link to child indexes, not every descendant.
- Link instead of copying state machines, schemas, ownership tables, or statuses.
- Use diagrams only when relationships are clearer than a short list or table, and explain the conclusion in prose.
- Reserve `MUST`, `MUST NOT`, `SHOULD`, `SHOULD NOT`, and `MAY` for documents declaring normative language.
