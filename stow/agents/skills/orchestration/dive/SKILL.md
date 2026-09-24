---
name: dive
description: Coordinate a DIVE Team through software design, implementation, verification, and explanation when Xavier requests or selects DIVE.
---

# DIVE

Coordinate one DIVE Team through Design, optional Critique, Implement, Verify, and Explain. Its DIVE Coordinator is a specialized Team Coordinator and the primary agent of its top-level Codex task. Ordinary Teams and DIVE Teams are peers. Either may belong to a saved Project or be projectless.

Apply the shared [Team scope guidance](../coordination-core/references/team-scope.md): prefer a concise topic-based Team title, with DIVE carried in the workflow assignment. Resolve repeated names through Project context and task identity.

Use the [DIVE Coordinator](../coordination-core/roles/dive-coordinator.md) role, separate from the Designer. Distinguish establishing a Team from executing its workflow:

- When Xavier requests a new DIVE Team, establish one top-level Codex task and assign its primary agent the exact role path `~/.agents/skills/orchestration/coordination-core/roles/dive-coordinator.md`, this skill, and the Team brief.
- When DIVE is selected for the current task, assume the DIVE Coordinator role there. When already assigned that role, execute the stages directly without creating another coordinator tier.

Load `$team-coordinator` for Team responsibilities and `$coordination-core` for shared coordination guidance. If stage delegation is unavailable, perform the stages sequentially and explain any limitation on independent Critique or Verify.

Use subagents when available. Give every fresh stage agent the exact DIVE role resource path and selected task evidence.

## Workflow

| Stage | Role resource | Output |
|---|---|---|
| Design | [design.md](references/design.md) | Current plan |
| Critique, when selected | [critique.md](references/critique.md) | Plan gate and findings |
| Implement | [implement.md](references/implement.md) | Working change and checks |
| Verify | [verify.md](references/verify.md) | Review gate and evidence |
| Explain | DIVE Coordinator | Consolidated outcome |

Use [Researcher](../coordination-core/roles/researcher.md) and [Explorer](../coordination-core/roles/explorer.md) for bounded evidence gathering. Helpers return evidence to the owning stage; that stage retains judgment and responsibility.

Maintain one current design. Scale designers, supporting roles, implementers, Critique, and Verify work to the outcome. Run independent implementation concurrently and sequence dependencies. Route ordinary corrections through Implement and Verify; route approach-changing findings through Design and selected Critique. Leave version-control decisions to Xavier after reporting the verified result.

Stage and helper returns normally stay within the Team. Surface them when they are the agreed useful return, require Xavier's decision or access, change the approved approach, or materially affect confidence, dependencies, or the next action. DIVE completion requires the agreed terminal gate and a consolidated outcome; a stage agent finishing is an intermediate event.

## Context and handoffs

Prefer a compact task brief over inherited conversation history. Include relevant history when it preserves intent or rationale that a summary would lose. When Xavier requests a fresh or empty-context assignment, disable inherited history and provide only the goal, constraints, decisions, and required references.

Start Critique and Verify with isolated context when supported. Otherwise supply a focused review brief and disclose the independence limitation. A fresh role assignment alone does not erase inherited context.

Give every handoff the intended behavior, relevant constraints and decisions, acceptance criteria, affected files, source artifacts, and a concise evidence summary. Prefer source locations over broad code dumps, logs, or transcripts.

## Design

Start Design with [design.md](references/design.md), the Team brief, relevant user context, established decisions and rationale, and the questions to resolve. Continue with the same Designer while its accumulated context remains useful.

Keep Design focused on investigation and a reviewable proposal. Prefer inline planning for simple proposals and use the requested presentation form when an artifact would help. When Design recommends documentation updates, experiments, or system changes beyond the assignment, present the proposal before implementation. Carry the current design into implementation and verification.

Use the shared [focused-collaboration guidance](../coordination-core/references/handoff.md#focused-collaboration-with-xavier) to choose when work benefits from Xavier joining this Team directly. Within the Team, keep the DIVE Coordinator as Xavier's normal conversation partner. Offer a direct conversation with the Designer when focused discovery would help define the goal and the coordinator lacks enough context to mediate. Use that arrangement when Xavier requests or accepts it.

Before implementation, establish that intent is explicit, consequential decisions are agreed, dependencies and coupled changes are understood, and acceptance checks are defined to verify the intended outcome.

## Critique

Prefer Design without a dedicated Critic. Add Critique when Xavier requests it, preserving that choice within its agreed scope. Recommend Critique when substantial drafting or repeated design revisions would materially benefit from independent assessment, and continue with the current arrangement until Xavier selects it.

When selected, start Critique with [critique.md](references/critique.md) and isolated context when supported. Give it the goal, constraints, current plan, consequential decisions, unresolved questions, and evidence references. Collect Ready, Revise, or Blocked; required corrections; optional improvements; user-intent questions; and assessment limits.

Route actionable critique to Design, factual questions to Researcher or Explorer when useful, and consequential intent questions to Xavier. Design owns plan revisions. Continue with the same Critic for materially revised decisions; minor corrections need only confirmation that they address the finding.

## Implement

Start an Implementer with [implement.md](references/implement.md) for each independently executable outcome. Supply the agreed design, assigned scope, dependencies, constraints, acceptance criteria, and expected verification.

Run independent outcomes concurrently within available capacity. Sequence dependent outcomes, and give coupled changes to one accountable Implementer. Protect concurrent work and follow repository conventions.

Resolve routine implementation choices from the design and evidence. Return unstated design assumptions or material departures to Design before affected work continues. Collect changes, checks, unresolved concerns, and dependencies for Verify.

## Verify

Start Verify with [verify.md](references/verify.md), using an independent agent and isolated context when supported. Supply the agreed behavior, acceptance criteria, constraints, implementer summary, test instructions, and access to the actual changes and surrounding code.

Collect Pass, Revise, or Blocked with supporting evidence, required corrections, optional improvements, checks, and verification limits.

- **Pass:** proceed to Explain.
- **Revise:** route corrections to the responsible Implementer and return the updated result to Verify.
- **Blocked:** resolve missing evidence or access and bring material decisions to Xavier.

Revisit Design, and Critique within its selected scope, when findings materially change the agreed approach. Keep ordinary implementation corrections within Implement and Verify.

## Explain

Return the consolidated outcome: what changed or was proposed, why it matters, the relevant review or verification evidence, remaining limitations, and any decision or follow-up.

Apply the DIVE Coordinator's artifact guidance when selecting evidence for presentation. Support completion claims with the applicable verification. A design-only DIVE Team concludes with the current plan, any selected critique, and unresolved questions.
