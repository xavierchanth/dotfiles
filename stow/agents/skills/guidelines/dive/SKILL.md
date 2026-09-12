---
name: dive
description: Use when the user requests the DIVE method or a DIVE group for coordinated design, implementation, and review.
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

Start each new DIVE group with Design, scaling the proposal to the task. Straightforward work may need only a brief statement of the intended change and how it will be checked. Carry established decisions, agreed plans, and completed outputs forward when resuming work, and use further discussion where unresolved choices could materially change the outcome.

## DIVE groups

Scope each DIVE group to one outcome with a clear brief, ownership boundaries, and acceptance criteria. Give its agents deliberately selected context relevant to that outcome.

Keep detailed investigation and routine discussion with the agents doing the work. Collect concise proposals, consequential questions, decisions, stage results, and blockers to guide the group.

Maintain one current design per group and carry it into implementation and verification. Share dependencies explicitly: transfer the decisions, interfaces, and constraints another group needs, and coordinate ownership where groups affect shared files.

Suggest separate app tasks when independent conversations, histories, or lifecycles would help. Create those tasks when the user requests them.

## Design

Start a Design subagent with [design.md](references/design.md), the group's brief, relevant user-provided context, established decisions and their rationale, and the questions to resolve. Communicate the user's elicitation preference, defaulting to discussion through you. Continue with the same subagent as the discussion develops.

Keep Design focused on investigation and an inline proposal for discussion. When Design recommends documentation updates, experiments, or system changes, share the proposal with the user first. Ensure findings inform decisions and unresolved assumptions remain visible.

Remain the user's normal conversation partner and act as the intermediary for designer questions. Answer from the conversation and established decisions, relaying supporting context to Design. Bring unresolved intent and consequential choices into the ongoing conversation, preserving the distinction between user input and proposed choices.

Dedicated elicitation is opt-in. Keep discussion parent-led when you can supply context or resolve a few missing facts through normal conversation. Offer direct designer elicitation when defining the goal, requirements, or acceptance boundary would benefit from a discovery conversation and you lack enough context to mediate usefully. Task size or a missing fact alone does not call for elicitation. An explicit user request for direct designer elicitation already establishes that preference; otherwise, offer it and relay the user's opt-in to Design. Stay involved and ensure the resulting input and rationale inform the current design.

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
