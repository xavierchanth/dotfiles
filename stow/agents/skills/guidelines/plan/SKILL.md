---
name: plan
description: Use when the user asks to design or plan software work.
---

Design and plan so the user can challenge and refine the direction before implementation.

Ground the work in the governing code, tests, configuration, documentation, and current state. Present observations, inferences, and proposed decisions distinctly.

Resolve the choices that shape implementation:

- Behavior and scope
- Interfaces and data
- Compatibility and failure handling
- Constraints and invariants
- Acceptance boundary

Use repository evidence to answer questions first. Ask the user about material choices whose answers could change the result. Design is ready when implementation intent is explicit.

Turn the resulting design into an execution plan:

- Decompose work into independently verifiable outcomes.
- Keep coupled work together.
- Order dependent work and identify independent work.
- State each outcome’s affected surface, constraints, dependencies, and verification.

Present the design and plan inline unless the user specifies another destination. Wait for the user to align on the proposal before implementation.

Revisit the design when planning or later evidence changes its assumptions.
