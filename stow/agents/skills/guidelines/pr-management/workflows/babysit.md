# Monitor or babysit a PR

Follow a PR until the requested milestone and act within the maintenance scope already authorized.

Distinguish a one-shot status request from continued monitoring. Observation-only watching reports actionable changes. Authorized maintenance can invoke [address feedback](address-feedback.md), [repair checks](repair-checks.md) and [prepare](prepare.md) to keep the description accurate.

Use [tracking](../capabilities/track.md) to establish a baseline, retain event state and schedule follow-up. For ongoing work use the host's supported automation mechanism when available; preserve the PR, scope, milestone and quiet-notification policy in its instructions.

On each check:
1. Refresh PR closure, head/base, checks, feedback and mergeability.
2. Stop on merged/closed state, cancellation, or the requested milestone.
3. Evaluate new actionable feedback and failures. Route authorized maintenance to its workflow; surface issues needing user judgment.
4. After a push, refresh the head and return to tracking. A fix is an intermediate outcome.
5. Notify on meaningful changes or required user action; stay quiet on unchanged or non-actionable state.

For “until ready,” readiness means required checks and approvals are satisfied, mergeability is confirmed, and no known actionable review items remain. It is a current-state assessment and does not authorize merging. For “until merged,” keep observing after readiness. If the endpoint is unspecified, default to merged/closed or user intervention and state that choice when starting.

When blocked, preserve monitoring context and explain the needed input. Stop or pause the owned monitoring mechanism as appropriate to the blocker and user request; do not claim a detached process guarantees future monitoring.
