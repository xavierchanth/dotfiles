---
name: invariants
description: Design or review domain models, APIs, state machines, wire contracts, and persistence schemas so invalid states are difficult or impossible to represent. Use when creating or changing lifecycle, status, error, request/result, Rust enum, TypeScript discriminated-union, or boolean/optional-field models.
---

Goal: make invalid states unrepresentable without overengineering.

- Identify invariants, states, transitions, and trust boundaries before types.
- Struct/object: values coexist. Enum/discriminated union: states exclude each other.
- Keep one representation per fact. Derive booleans/status from authoritative data.
- Use `Option` only for independently optional data. Use variants when fields depend on state.
- Keep failure outside valid state with `Result<T, E>`. Model retry/close/failure disposition as variants, not conflicting flags.
- Use semantic newtypes, private fields, and smart constructors for validated IDs, times, hashes, URLs, and bounds.
- Parse untrusted input once at the boundary. Internal code receives validated domain types.
- Separate wire/persistence DTOs from strict domain types when storage or compatibility requires looser shapes. Convert explicitly.
- Design interfaces from concrete caller needs. Expose the smallest useful contract; keep representation and implementation details private.
- Make interface contracts preserve invariants: specify valid inputs, guaranteed outputs, failure modes, and permitted state changes. Every implementation must honor the same contract.
- Use adapters to translate external APIs and storage into domain-owned contracts. Keep vendor types, transport details, and boundary validation inside the adapter.
- Use strategies for interchangeable behavior under one contract. Prefer a function for a single operation, an interface for related operations, and an enum when alternatives are closed and exhaustiveness matters.
- Introduce abstractions at meaningful boundaries or where behavior actually varies. Avoid one-to-one wrappers and speculative extension points that add no guarantees or hide no complexity.
- Encode transitions in methods or reducers. Prevent arbitrary lifecycle mutation.
- Preserve Rust tagged enums as TypeScript discriminated unions. Do not flatten them into optional-field bags.
- Prefer exhaustive security/domain states. Version external contracts; reject unknown security state.
- Use typestate for local compile-time sequences; tagged enums across async, persistence, and language boundaries.
- Prefer zero-cost newtypes/enums. Accept bounded boundary conversion or async dispatch cost when it improves correctness and auditability.
- Before finishing, list still-representable invalid combinations and refine the model or document the runtime enforcement point.
