# Explain the change

Write for someone who has not seen the conversation. Follow repository templates and title conventions, scaling detail to the change.

Cover these reader needs, combining sections for small changes:

- **Intent and design:** problem, intended outcome, important boundaries, chosen approach and consequential rationale. Use before/after examples where helpful. Explain constraints, invariants and tradeoffs that help assess the design.
- **Review guidance:** conceptual shape, component relationships, useful entry points or reading order, subtle interactions and specific questions needing judgment. Explain PR dependencies and merge ordering when relevant.
- **Verification and confidence:** checks actually performed, results, what they establish, reproducible steps and meaningful gaps. Separate completed evidence from suggested checks.
- **Delivery implications:** compatibility, migrations, rollout order, recovery or changelog text when relevant to delivery.

Use available design and verification inputs and reconcile them with the implemented result. Link canonical documents while keeping the PR understandable on its own. Preserve agreed rationale; distinguish inference from established intent.

Describe the final scope rather than development chronology or a file inventory. Refresh the title/body when scope changes and qualify evidence that no longer covers the current changes. Use closing issue references only for issues actually resolved.
