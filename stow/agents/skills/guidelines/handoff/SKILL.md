---
name: handoff
description: Use when asked to push or hand off work to a named machine, or bring it back locally.
---

# Handoff

- Move work to a workspace on a named machine, continue execution there, and bring the result back when requested.
- Treat "push this to hades" and "hand off this work to zeus" as machine handoffs. Resolve the name as a destination machine; distinguish it from a person, agent role, or Git remote.
- Read [homelab.md](references/homelab.md) to resolve machine names. For Codex, read [codex.md](references/codex.md) before acting. For other harnesses, establish their supported transfer and continuation mechanism before promising a handoff.

## Identify and prepare

- Resolve the work being moved, its current machine, repository, working directory, and intended destination workspace.
- Preserve the existing task and conversation when supported. Create a separate assignment only when the user asks for independent work.
- Establish the exact base and working changes needed by the assignment, including required new files and local inputs.
- Match the destination repository and project scope. Resolve machine names through the bundled reference and live harness identifiers.
- Check the destination environment needed for this assignment. Configuration describes intended setup; verify availability when it matters to execution.
- Use an isolated destination workspace when work would otherwise compete for the same working copy. Give each writable workspace one accountable assignment.
- Respect the workspace manager's placement and lifecycle. Verify the transfer mechanism supports the actual source layout and version-control state.
- Give the receiving task a bounded instruction: outcome, scope, constraints, and completion checks.

## Push and continue

- Use the active harness's supported handoff mechanism. Settle or interrupt active execution as that mechanism requires, honoring any user instruction to finish the current step first.
- Preserve the transfer identifier and reconcile delayed or ambiguous results before attempting another move.
- Confirm the destination machine, task, workspace, and expected changes before reporting success.
- Start or resume the assignment after transfer as requested. Transfer completion alone does not establish that execution has started.
- If the mechanism cannot move the calling task or reach the destination, give the specific supported next action. Do not silently substitute a different task, machine, or base.

## Wait and guide

- Use supported observation and follow-up tools to inspect progress, deliver instructions, and surface required input.
- Distinguish completed work, required input, failed execution, and an unreachable machine. Preserve the last known state when current observation is unavailable.
- For "bring it back when done", arrange the supported wait or scheduled follow-up and use the assignment's completion condition.
- Continue addressing the same task through its current location rather than starting another copy after an uncertain response.

## Bring back and close

- Resolve "here" from the caller's current machine and identify the intended destination workspace. Check for unrelated local changes before selecting a checkout.
- Settle remote execution, transfer the work back, and verify arrival before continuing locally.
- Inspect the returned changes and run the checks appropriate to the local environment. Integrate into other local work only within the user's requested scope.
- Handle archival and workspace deletion separately from transfer. Remove only selected inactive workspaces whose changes are safely retained.
- Report the current task location, what arrived, verification results, and any remaining limitation.
