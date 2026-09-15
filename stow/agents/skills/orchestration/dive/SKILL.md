---
name: dive
description: Use when Xavier requests DIVE or a DIVE group for coordinated software design, implementation, verification, and explanation.
---

# DIVE

Coordinate one software outcome through Design, optional Critique, Implement, Verify, and Explain. Load `$coordination-core` for context selection, delegation, model selection, handoffs, attention, and evidence. DIVE works standalone in a saved Project or projectless context and does not require a Team.

Every DIVE group has the logical Group Coordinator role, separate from the Designer. Distinguish establishing a group from executing one:

- When establishing a new group, assign a dedicated Group Coordinator agent the exact role path `~/.agents/skills/orchestration/coordination-core/roles/group-coordinator.md`, this skill, and the group brief.
- When already assigned the Group Coordinator role, execute the stages directly without creating another Group Coordinator.

If you cannot delegate a Group Coordinator, explicitly assume that role and run the other stages sequentially. Preserve role boundaries as far as possible. Report that execution is degraded and identify any loss of independent Critique or Verify.

Use subagents when available. Give every fresh stage agent the exact DIVE role resource path and selected task evidence. Supporting roles do not inherit model or reasoning overrides from the agent that delegates to them unless that inheritance is explicitly requested; select them independently.

## Workflow

| Stage | Role resource | Output |
|---|---|---|
| Design | [design.md](references/design.md) | Current plan |
| Critique, when selected | [critique.md](references/critique.md) | Plan gate and findings |
| Implement | [implement.md](references/implement.md) | Working change and checks |
| Verify | [verify.md](references/verify.md) | Review gate and evidence |
| Explain | Group Coordinator | Consolidated outcome |

Use [Researcher](../coordination-core/roles/researcher.md) and [Explorer](../coordination-core/roles/explorer.md) for bounded evidence gathering. Helpers return evidence to the owning stage; that stage retains judgment and responsibility.

Maintain one current design. Scale designers, supporting roles, implementers, Critique, and Verify work to the outcome. Run independent implementation concurrently and sequence dependencies. Route ordinary corrections through Implement and Verify; route approach-changing findings through Design and selected Critique.

## Context and handoffs

Prefer a compact task brief over inherited conversation history. Include relevant history when it preserves intent or rationale that a summary would lose. When Xavier requests a fresh or empty-context assignment, disable inherited history and provide only the goal, constraints, decisions, and required references.

Start Critique and Verify with isolated context when supported. Otherwise supply a focused review brief and disclose the independence limitation. A fresh role assignment alone does not erase inherited context.

Give every handoff the intended behavior, relevant constraints and decisions, acceptance criteria, affected files, source artifacts, and a concise evidence summary. Prefer source locations over broad code dumps, logs, or transcripts.

## Design

Start Design with [design.md](references/design.md), the group brief, relevant user context, established decisions and rationale, and the questions to resolve. Continue with the same Designer while its accumulated context remains useful.

Keep Design focused on investigation and an inline proposal. When it recommends documentation updates, experiments, or system changes, present the proposal before implementation. Carry the current design into implementation and verification.

Keep the assigning coordinator as Xavier's normal conversation partner. Offer a direct conversation with the Designer when focused discovery would help define the goal and the coordinator lacks enough context to mediate. Use that arrangement when Xavier requests or accepts it.

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

Return the consolidated outcome:

- what changed and why;
- what was reviewed and verified;
- the review gate and remaining limitations;
- relevant artifacts and follow-up work; and
- any decision Xavier or the assigning coordinator needs to make.

Support completion claims with verification evidence. A design-only DIVE concludes with the current plan, selected critique, and unresolved questions.
