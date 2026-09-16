# Decision Records / ADRs

Use for a durable record of a consequential decision, including architectural decisions.
A decision memo helps an audience reach a choice; a decision record preserves the
context, chosen approach, and rationale for future readers. A draft ADR can support
the discussion and become the record when the decision is made.

## Structure

Use a short decision brief followed by supporting reasoning. The brief states the
conclusions; the reasoning explains them. Follow existing project conventions when supplied.

```markdown
# <Decision name>

## Decision Brief

- **Status:** Draft / Approved / Rejected / Superseded
- **Objective:** What are we trying to achieve?
- **Decision:** What approach are we choosing or proposing?
- **Rationale:** Why this approach?
- **Implications:** What significant tradeoffs or commitments follow?

## Reasoning

### Context

Explain the situation, problem, and constraints that make this decision necessary.
Include scope boundaries where they affect the choice.

### Alternatives and Tradeoffs

Explain the meaningful options and why the selected approach best serves the
objective. Include the consequences that influenced the choice.

### Approach

Describe how the decision works in practice, with enough detail to make its meaning
clear. Link supporting specifications when appropriate.
```

Select the actual status. Keep the other brief fields to a sentence or two each,
then expand the reasoning according to the decision's complexity. Use version history
for revision dates rather than maintaining a separate last-updated field.

## Develop and Maintain the Record

Capture the decision question, source discussions, constraints, and available evidence
before filling the structure. Organize around the decision rather than the chronology
of the conversation. Separate facts and constraints from preferences and assumptions.

Use alternatives where they explain a real choice. Record why an approach was chosen
with enough context for a future reader to understand it without the original participants.
Scale detail to the decision; link supporting specifications instead of duplicating them.

Keep proposal, acceptance, and implementation distinct. Reflect an actual decision in
the status; drafting or editing the record does not establish acceptance. An approved
decision may still await implementation.

When a later decision replaces an earlier one, preserve the historical rationale and
link the superseding record according to the project's conventions. This format guides
the writing; it does not introduce a new organizational approval process.
