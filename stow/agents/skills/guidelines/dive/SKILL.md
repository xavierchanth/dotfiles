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

Start a Design subagent with [design.md](references/design.md), the request, established decisions, relevant context, and the questions to resolve. Continue with the same subagent as the discussion develops.

Bring material choices to the user and relay their feedback to the Design subagent. Ensure the plan carries their answers and the reasons behind decisions.

Before implementation, establish that the plan provides clear intent, verifiable outcomes, dependencies, coupled changes, and acceptance checks. Return unresolved questions to Design.

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
