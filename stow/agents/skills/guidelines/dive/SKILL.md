---
name: dive
description: Use when the user requests the DIVE method or a DIVE group for coordinated design, implementation, and review.
---

Coordinate Design, Implement, Verify, and Explain using the available capabilities, adding Critique when selected by the user. Give each delegated role deliberately selected context and a clear outcome. The user-facing coordinator owns user discussion, direction, and final acceptance; progression between stages may be delegated within an explicit brief.

Give each subagent an explicit role and instruct it to read its role resource directly.

## Execution adaptation

Use subagents when available. If delegation is unavailable, perform the stages sequentially in the current session, read the corresponding role resources, and disclose that verification and any selected critique were not independent. Apply the stage instructions below through the available mechanism.

Prefer a compact task brief over inherited conversation history. Include relevant history when it preserves intent or rationale that a summary would lose. When the user requests a fresh or empty-context assignment, disable inherited conversation history and provide only a compact task brief containing the goal, constraints, and required references. When context isolation is available, start Critique and Verify without inherited conversation history. When it is unavailable, supply a focused review brief and disclose the independence limitation; a fresh role assignment alone does not erase existing context.

Use agent continuation, parallel execution, and direct designer elicitation only when supported. Otherwise, transfer the current decisions and evidence in a concise handoff, sequence work, and relay designer questions through the coordinator.

| Stage | Role | Output |
|---|---|---|
| Design | Designer | Plan |
| Critique (when selected) | Critic | Plan readiness and findings |
| Implement | Implementer | Code |
| Verify | Verifier | Review gate |
| Explain | Coordinating agent | Summary of results |

## Model selection

Use the `sol` alias with `low` reasoning for every delegated coordinator, stage, and supporting role. Roles describe responsibilities and context, not model profiles. Select a different model or reasoning level only when the user requests it or the assignment has a concrete need that justifies the override.

| DIVE alias | Model ID | Reasoning when omitted |
|---|---|---|
| `astra` | `gpt-6-astra` | `low` |
| `sol` | `gpt-5.6-sol` | `low` |
| `terra` | `gpt-5.6-terra` | `low` |
| `luna` | `gpt-5.6-luna` | `low` |

Model selection and reasoning selection are independent. A DIVE alias or model ID without a reasoning level resolves to the reasoning in this table. An explicit reasoning level overrides it for that assignment. State overrides briefly and carry them forward within their selected scope.

Match a DIVE alias or exact model identifier from the table. For an unavailable model, prefer a user-established equivalent; otherwise use the configured default and state the fallback. Apply reasoning settings only when supported. If the user explicitly requires an unavailable model or capability, ask how to proceed with the affected stage.

## Context and usage

Keep investigation, drafting, and implementation with the assigned agents. Request concise findings and decisions from Critique and Verify while preserving the evidence needed for sound judgment. Return plan revisions to Design and implementation corrections to Implement.

Handoffs should contain the intended behavior, relevant constraints and decisions, acceptance criteria, affected files, and a concise evidence summary. Provide access to source artifacts rather than copying broad code dumps, logs, or conversation transcripts. Preserve enough context for independent assessment and expand reads when evidence warrants it.

Treat DIVE as an adaptive cycle. Revisit stages as evidence changes, run independent work concurrently, and scale decomposition and verification to the work. A design-only request concludes with the current plan, any selected critique, and unresolved questions.

Start each new DIVE group with Design, scaling the proposal to the task. Straightforward work may need only a brief statement of the intended change and how it will be checked. Carry established decisions, agreed plans, and completed outputs forward when resuming work, and use further discussion where unresolved choices could materially change the outcome.

## DIVE groups

Scope each DIVE group to one outcome with a clear brief, ownership boundaries, and acceptance criteria. Give its agents deliberately selected context relevant to that outcome.

Keep detailed investigation and routine discussion with the agents doing the work. Collect concise proposals, consequential questions, decisions, stage results, and blockers to guide the group.

Treat stages as responsibilities rather than a fixed arrangement of agents. Prefer one designer for a cohesive outcome. Use multiple designers when distinct concerns benefit from focused work, naming an owner to reconcile their contributions into one current design. Share a designer across groups when common interfaces or decisions benefit from consistent ownership.

Use one implementer for coupled design contributions and multiple implementers for independently executable parts of an agreed design. Make synthesis and integration ownership explicit, resolve conflicting proposals before dependent implementation, and verify combined behavior across affected groups.

The user-facing coordinator may delegate coordination of one or more groups when managing dependencies or coordination load would benefit. Instruct the delegated coordinator to read this SKILL.md as its shared workflow, loading role resources as needed. Give it outcomes, established decisions, dependencies, decision authority, and matters to escalate. Let it progress stages and resolve routine dependencies within that brief. Route unresolved user intent and material changes in direction through the user-facing coordinator. A delegated coordinator may assign its own stage agents or further coordinators when supported and useful for a distinct outcome, carrying the same scope and authority boundaries into their briefs. Return concise results, verification evidence, and escalations to the assigning coordinator; user discussion, direction, and final acceptance remain with the user-facing coordinator. Prefer direct coordination when another layer would mainly relay messages.

Maintain one current design per group and carry it into implementation and verification. Share dependencies explicitly: transfer the decisions, interfaces, and constraints another group needs, and coordinate ownership where groups affect shared files.

Suggest separate user-facing tasks or sessions when independent conversations, histories, or lifecycles would help and that capability is available. Create them when the user requests them.

## Design

Start a Design subagent with [design.md](references/design.md), the group's brief, relevant user-provided context, established decisions and their rationale, and the questions to resolve. Communicate the user's elicitation preference, defaulting to discussion through you. Continue with the same subagent as the discussion develops.

Keep Design focused on investigation and an inline proposal for discussion. When Design recommends documentation updates, experiments, or system changes, share the proposal with the user first. Ensure findings inform decisions and unresolved assumptions remain visible.

The user-facing coordinator remains the user's normal conversation partner. An assigned coordinator mediates designer questions using the supplied context and established decisions, relaying unresolved intent and consequential choices through the user-facing coordinator. Preserve the distinction between user input and proposed choices.

Dedicated elicitation is opt-in. Keep discussion parent-led when you can supply context or resolve a few missing facts through normal conversation. Offer direct designer elicitation when defining the goal, requirements, or acceptance boundary would benefit from a discovery conversation and you lack enough context to mediate usefully. Task size or a missing fact alone does not call for elicitation. An explicit user request for direct designer elicitation already establishes that preference; otherwise, offer it and relay the user's opt-in to Design. Stay involved and ensure the resulting input and rationale inform the current design.

Use the lightweight plan structure in [design.md](references/design.md) to preserve the original goal, key design decisions, implementation plan, and acceptance checks with open questions. Before implementation, establish that intent is explicit, consequential decisions are agreed, dependencies and coupled changes are understood, and checks establish the intended outcome. Return unresolved questions to Design.

Present the plan inline unless the user specifies another destination. Align with the user before implementation, and return new evidence that changes the agreed direction to Design.

## Critique

Prefer Design without a dedicated critic. Add Critique when the user requests it, preserving that choice within its agreed scope.

The parent coordinator should recommend Design with Critique when substantial drafting or repeated design revisions would benefit from independent assessment. Explain the expected benefit briefly: keeping plan generation and revision with the designer while a separate critic tests consequential decisions.

A focused design subtask may also benefit when it requires substantial exploration or drafting around a bounded decision. Scope the recommendation to the work that benefits. Use expected design effort, uncertainty, and the usefulness of independent assessment to guide the recommendation; project size alone is insufficient.

Treat the recommendation as a proposal. Continue with the current arrangement until the user selects it, then carry the selection forward within its agreed scope. When critique is added to an existing design, preserve useful designer context and established decisions.

When selected, Critique is a checkpoint within Design: Design → Critique → Implement → Verify → Explain. Assign a critic with [critique.md](references/critique.md) and isolated context when supported to assess the prepared plan before implementation.
Supply a compact, self-contained brief: the user's goal, constraints, proposed plan, consequential decisions, unresolved questions, and references to supporting evidence. The critic can inspect relevant source material when needed. Collect plan readiness, required changes, optional improvements, questions requiring user input, and assessment limits.

Resolve the critique as coordinator. Route actionable feedback to Design, factual investigation to a researcher or explorer when useful, and consequential intent questions to the user. Design owns revisions. Resolve required changes and blocking questions before implementation, carrying existing user agreement forward without asking for approval again when the revision remains within it.

Continue with the same critic for materially revised decisions. Minor corrections do not require another full pass; confirm that they address the finding. Return implementation or verification findings to Design when they materially change the approach, and repeat selected critique when reassessment is warranted.

## Supporting roles

Give each helper a bounded question, relevant context, and an expected evidence-based result. Design and Critique may each delegate bounded evidence gathering to supporting researchers or explorers. Helpers return evidence to the owning stage, while the Designer or Critic retains judgment, synthesis, and responsibility for the result. Select each supporting role's model and reasoning independently. Supporting roles do not inherit model or reasoning overrides from the agent that delegates to them unless that inheritance is explicitly requested. Use [researcher.md](references/researcher.md) for source investigation and synthesis, and [explorer.md](references/explorer.md) for code and behavior mapping. Return findings to the owning stage so its agent maintains the plan or implementation.

## Implement

Start an Implement subagent with [implement.md](references/implement.md) for each independently executable outcome. Give it the agreed plan, relevant context, assigned scope, dependencies, constraints, acceptance criteria, and expected verification.

Run independent outcomes concurrently within the available capacity. Sequence dependent outcomes so each receives the completed prerequisite. Assign coupled changes to one accountable subagent.

Use follow-up messages to resolve questions, supply evidence, and correct drift. Continue with the same subagent when its accumulated context remains useful.

Resolve escalated design questions through Design and involve the user in material choices. Establish alignment before the affected implementation resumes.

Collect each agent’s changes, checks performed, results, and unresolved concerns. Resolve outstanding dependencies and assemble the completed outcomes for verification.

## Verify

Start Verify with [verify.md](references/verify.md), using an independent agent and isolated context when supported. Supply a compact brief with the agreed behavior, acceptance criteria, relevant constraints, implementer’s summary, test instructions, and access to code and diffs. Include the combined result across implementation outcomes in its scope. On corrections, prefer continuing with the same reviewer using the changes since its last review and new evidence.

Collect its review gate, supporting evidence, required corrections, optional improvements, and verification limits.

- Pass — proceed to Explain.
- Revise — route corrections to the responsible Implement subagent, then return the updated result for verification.
- Blocked — resolve missing evidence or access, and bring material decisions to the user.

Revisit Design, and Critique within its selected scope, when findings materially change the agreed approach. Track required corrections through verification and use the review evidence to establish final acceptance.

## Explain

Summarize the result against the user’s intended outcome:

- What changed and why
- What was reviewed and verified
- The review gate and any remaining limitations
- Relevant artifacts and follow-up work

Support completion claims with the verification evidence. Keep the explanation proportional to the work and make any decision needed from the user clear.
