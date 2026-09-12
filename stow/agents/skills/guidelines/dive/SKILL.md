---
name: dive
description: Use when the user requests DIVE or coordinated software work through subagents, including design, implementation, and review.
---

Coordinate work through the harness’s subagent tools. Give each subagent deliberately selected context and a clear outcome. Own user discussion, direction, progression between stages, and final acceptance.

Give each subagent an explicit role and instruct it to read its role resource directly.

Design and Implement may inherit relevant conversation history.

| Stage | Default profile | Output |
|---|---|---|
| Design | `design` | Plan |
| Implement | `implement` | Code |
| Verify | `verify` | Review gate |
| Explain | Coordinating agent | Summary of results |

Read the model resource matching the active harness: [Codex](references/models/codex.md) or [OpenCode](references/models/opencode.md). Resolve each profile to its model and reasoning settings when assigning a subagent.

Use standard profiles unless the user requests a different profile. Available alternatives include `design-large`, `implement-large`, `verify-large`, and `flash`.

Match full model IDs first, then documented harness aliases. When the harness or a required profile is unconfigured or unavailable, ask the user to choose a mapping.

Treat DIVE as an adaptive cycle. Revisit stages as evidence changes, run independent work concurrently, and scale decomposition and verification to the work. A design-only request concludes with the plan.

Enter the cycle at the stage matching the request and available work. Carry existing decisions and completed outputs forward.

## Design

Start a Design subagent with [design.md](references/design.md), the request, relevant user-provided context, established decisions and their rationale, and the questions to resolve. Continue with the same subagent as the discussion develops.

Have Design investigate uncertainties that materially affect the approach, using research or small experiments where useful. Ensure findings inform decisions and unresolved assumptions remain visible.

Act as the intermediary for designer questions. Before asking the user, check the conversation and established decisions for a clear answer. When the user has already supplied the answer, relay it directly to Design with the supporting context.

When answering would require a new assumption, a decision on the user’s behalf, or clarification of ambiguous or conflicting context, ask the user about the unresolved part and relay their response to Design. Preserve the distinction between established user intent and proposed choices. Ensure the plan carries their answers and the reasons behind decisions.

Use the lightweight plan structure in [design.md](references/design.md) to preserve the original goal, key design decisions, implementation plan, and acceptance checks with open questions. Before implementation, establish that intent is explicit, consequential decisions are agreed, dependencies and coupled changes are understood, and checks establish the intended outcome. Return unresolved questions to Design.

Present the plan inline unless the user specifies another destination. Align with the user before implementation, and return new evidence that changes the agreed direction to Design.

## Implement

Start an Implement subagent with [implement.md](references/implement.md) for each independently executable outcome. Give it the agreed plan, relevant context, assigned scope, dependencies, constraints, acceptance criteria, and expected verification.

Run independent outcomes concurrently within the harness’s capacity. Sequence dependent outcomes so each receives the completed prerequisite. Assign coupled changes to one accountable subagent.

Use follow-up messages to resolve questions, supply evidence, and correct drift. Continue with the same subagent when its accumulated context remains useful.

Resolve escalated design questions through Design and involve the user in material choices. Establish alignment before the affected implementation resumes.

Collect each agent’s changes, checks performed, results, and unresolved concerns. Resolve outstanding dependencies and assemble the completed outcomes for verification.

## Verify

Start a fresh Verify subagent with [verify.md](references/verify.md). Build its starting context from the agreed plan, acceptance criteria, implementer’s summary, relevant test instructions, and access to code and diffs. Include the combined result across implementation outcomes in its scope.

Collect its review gate, supporting evidence, required corrections, optional improvements, and verification limits.

- Pass — proceed to Explain.
- Revise — route corrections to the responsible Implement subagent, then return the updated result for verification.
- Blocked — resolve missing evidence or access, and bring material decisions to the user.

Revisit Design when findings change the agreed approach. Track required corrections through verification and use the review evidence to establish final acceptance.

## Explain

Summarize the result against the user’s intended outcome:

- What changed and why
- What was reviewed and verified
- The review gate and any remaining limitations
- Relevant artifacts and follow-up work

Support completion claims with the verification evidence. Keep the explanation proportional to the work and make any decision needed from the user clear.
