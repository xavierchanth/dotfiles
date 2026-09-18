# Assignment and return

Scale the assignment to its consequences and complexity. A simple assignment may fit in one natural sentence. Add structure when it helps the agent make a sound decision.

A useful assignment communicates:

- the intended outcome;
- only the context needed for the assignment;
- relevant scope, workspaces, sources, or access;
- boundaries whose violation would matter; and
- the expected return and destination when they are not already obvious.

For interdependent Teams, include the producing and consuming destinations, useful handoff, acknowledgment, and escalation points when they are not obvious. Iris establishes this reporting contract and handoff chain; Teams carry out routine peer coordination directly under [handoff.md](handoff.md).

Ask for missing information when it would materially change the work and cannot be inferred safely. Resolve routine choices using the available context.

A useful return communicates the result, proportionate evidence, relevant artifacts, and anything needing the recipient's attention. The Codex task is the durable record; live harness state tracks execution.

## Team ownership and return routing

When a Team has a clearly assigned owning Iris, that Iris is its default oversight return destination. While ownership remains in force, the Team must proactively send meaningful progress, decisions needed, blockers, and completion to that Iris through the harness's task-messaging mechanism. Established operational handoffs also go directly to the consuming Team; keep Iris informed with a concise state delta or reference rather than asking it to relay the details. A final response in the Team's own task alone does not deliver these returns, and delivery does not depend on Iris waiting or polling. Send concise, evidence-backed deltas with useful artifact references; keep routine Worker activity and unchanged status within the Team. Surface urgent authority requests and material failures promptly.

The initial assignment should identify the owning Iris and return task when they are not obvious. Preserve the resolved task ID and host when needed, alongside the Team's Project context, so returns reach the correct Iris even across Projects or shared workspace paths. Project membership, a shared path, or a similar task title alone does not establish ownership. When ownership is unclear, resolve it from the assignment and live harness context or ask one concise question before sending to an uncertain recipient; continue independent work meanwhile.

Honor explicit disowning and reassignment. The coordinator handling an authorized ownership change communicates the new routing or removal to the Team and affected Iris tasks, transfers pending returns with the handoff, and tracks failed or uncertain notifications as pending. Update the Team's coordination context and route subsequent returns to the new owner or other explicitly named recipient. Once ownership is removed, the Team no longer owes returns to its former Iris. A Team without an owning Iris follows its explicit assignment's return destination, or returns to Xavier in its own task when directly assigned there.

Treat a failed or uncertain send as pending delivery. Inspect the destination's available context before retrying an uncertain send to avoid duplicate updates. Successful delivery to Iris fulfills the Team's routing obligation; Iris remains responsible for assessing the result and delivering it to Xavier at the appropriate attention boundary.

## Artifact handoffs

Carry the intended use of an artifact through the assignment and return: whether Xavier wants to see, inspect, review, compare, hear, decide on, or retain it. A compact natural reference should explain what it is, why it matters, how it is best experienced, and where its canonical version belongs. Include only the detail needed to make that handoff useful.

Prefer a brief explanation and a direct reference over reproducing the artifact in the conversation. Add the relevant revision, section, or comparison point when it helps the recipient inspect the intended material.

Across isolated workspaces, preserve the owning task, canonical path or URL, and any host or access context needed to locate the artifact. Prefer presenting the canonical version; copy or export it when the requested delivery or retention requires that. If its location is temporary, arrange a durable home within the assignment's scope or make the retention limitation clear.
