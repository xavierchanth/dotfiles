# Track changes over time

Retain enough state to recognize meaningful changes across checks:
- PR identity, requested endpoint and authorized maintenance scope.
- Last observed base/head SHAs, checks and mergeability.
- Published feedback IDs, edits and resolution state.
- Actions taken, retry counts and outstanding blockers.

Start with existing unresolved feedback, not only newly arriving comments. Deduplicate actions while recognizing edited comments and unresolved follow-ups. Reassess evidence when the head changes.

Use the host's supported scheduler or automation mechanism for ongoing monitoring when available. Store resumable state outside disposable review clones. Update an existing owned monitor rather than creating duplicates.

If using an active-session loop, use bounded waits and adaptive polling: check more promptly during running CI or after changes, and back off during quiet periods. Remain responsive to user input. State the mechanism actually running; ending a turn with an unowned background process is not a reliable handoff.

Notify on meaningful progress, new blockers, required decisions or completion. Keep unchanged/non-actionable checks quiet. Stop and clean up the owned monitor at its endpoint or cancellation. Return current state to the calling workflow.
