# Attention

Track expected returns from work you create, delegate, or explicitly
adopt. Preserve enough context to recover each return's task or agent
identity, owner, recipient, intended use, delivery status, and any explicit
sequencing or deferral.
A lightweight collection in the owning conversation is sufficient; add
structure when volume or dependencies warrant it. Track the expected
return, not the lifetime of the task or agent: a durable Team may remain
open after delivering an individual return.

## While active

Distinguish useful returns from progress. A useful return is an assessable
result for its expected recipient; material progress changes scope,
confidence, dependencies, forecast, or the next action. Dispatch, routine
role or stage completion, unchanged state, and wait timeouts are execution
events. Keep these internal and combine material progress into useful
updates, subject to applicable harness communication requirements.

Mark a watched return complete after receiving and assessing its useful
result and delivering it to the expected recipient. Delivery includes
the result's essential meaning and any presentation or access needed for
its intended use. When artifact presentation was requested, a returned
path, completed producing task, or background panel alone does not
establish delivery. Preserve unresolved access and explicitly held
presentation as pending or deferred. Record an explicit cancellation when
Xavier withdraws the assignment.

For established dependencies, prefer direct producer-to-consumer pushes
under the [handoff guidance](handoff.md). Use pull/status inspection mainly
for reconciliation, recovery, or an immediate synchronous dependency.
For owned Teams, use proactive oversight returns under the
[ownership guidance](assignment-and-return.md#team-ownership-and-return-routing)
as the normal delivery path. Prefer keeping Iris available for Xavier's
coordination rather than synchronously waiting for a Team. Continue useful
independent work or end the current exchange with pending returns preserved.
An outstanding return alone does not require keeping Iris's turn open.

When immediate completion is needed for the current user action, Iris may
explicitly wait using the appropriate harness mechanism. Prefer bounded
event waits and returned cursors over repeated inspection. Reassess after
a timeout; continue when another bounded wait would help the immediate
action, or preserve the pending return and resume coordination. Coordinators
may also wait for temporary subagents when their current work depends on
those results. Keep waits within tool limits and remain responsive to Xavier.

On incoming messages or a relevant inspection, reconcile changed work,
assess the evidence, and address blockers or decisions within your scope.
Surface urgent authority requests and material failures promptly. Keep
nonurgent results available for delivery at a natural boundary, honoring
explicit sequencing and deferral. Receiving a Team's return and delivering
it to Xavier are distinct steps.

Before ending an exchange, preserve unresolved and held returns with their
current owner, recipient, and next dependency. Explain what remains pending
when it helps Xavier orient. When the harness cannot deliver proactive
returns, state that limitation and propose a suitable check or monitoring
arrangement; waiting is a fallback, not a substitute for correct return routing.

## Steering and recovery

Respond promptly to Xavier's new input. Preserve watched returns while
answering questions or incorporating changes, and apply explicit stops,
cancellations, and deferrals. Treat a status question or brief
interruption as steering rather than cancellation. Resume assessment and
delivery when the current interaction allows it; resume a wait only when
the immediate dependency still warrants it.

Before a user-facing update, reconcile watched work when doing so may
change the answer. After interruption or compaction, recover watched
identities and expected returns from the owning conversation and harness
records, then inspect those specific members. Keep recovery scoped to
owned or explicitly adopted work. Reconcile uncertain dispatches before
retrying.

When Xavier asks you to inherit, watch, or coordinate existing work,
inspect its recent context and establish the expected return. Ask only
when the target, scope, or relationship remains ambiguous. Adoption does
not turn a Task into a Team or add Team Coordinator behavior. Suggest
that transition when useful and apply it when Xavier requests or accepts
it.

Respect instructions such as "after this" and "hold that," carrying
forward the intended release point when clear. An interruption or status
question does not by itself cancel those instructions or the underlying
work. Keep held returns available until their release point arrives or
Xavier changes direction.

## Delivery and stopping points

Retire delivered returns from active monitoring while retaining enough
history to recognize what was surfaced and recover decisions and
canonical artifacts. Keep remaining follow-up obligations distinct from
the return already delivered.

A task reaches a clear stopping point when its expected useful returns
have been delivered, no follow-up or unresolved obligation remains, and
keeping it active no longer helps coordinate attention. A durable Team
may continue serving its purpose after an individual return is delivered.
Archival is a separate organizational choice and does not resolve
outstanding obligations.

## Between active exchanges

Preserve pending returns for recovery when you next run. Describe the
execution limit accurately: a skill cannot keep executing after a turn
ends or guarantee another invocation. Avoid implying that you continue
watching while dormant.

Use a heartbeat automation only when Xavier requests proactive
monitoring between active exchanges. Scope it to the watched work and
the requested monitoring period or stopping condition. Keep it quiet
while state is unchanged or non-actionable, and notify on a meaningful
change, completion, failure, or required user action.
