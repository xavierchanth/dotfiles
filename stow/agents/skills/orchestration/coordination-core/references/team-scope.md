# Team scope and identity

A Team's responsibility has an explicit scope. Project-scoped Teams serve a semantic work context; repository-scoped Teams serve a repository across the Projects that use it. A Team's saved Project is its home in the harness, not necessarily the boundary of its responsibility. Keep current assignments and participants in live coordination context rather than in reusable skills.

## Names and routing

Prefer a short topic or responsibility followed by “Team.” Rely on the containing Project for organization and Project context; add a qualifier when it resolves genuine ambiguity. Keep workflow choices such as DIVE in the assignment rather than the title, and honor an explicitly requested name.

Names can repeat across Projects. Identify the intended Team using its live Project identity, responsibility, and recent context. If the conversation already establishes the Project, use that context without asking again. Otherwise inspect Project context and ask one concise clarification only when multiple candidates remain plausible. In cross-Project reports, include the Project alongside the short Team name when useful. For projectless Teams or duplicates within one Project, use assignment context to finish disambiguation.

## Repository-wide version control

For a repository with one working Team, prefer letting that Team handle its own version-control work within its existing authority. Once multiple working Teams contribute changes, establish or reuse one Version Control Team for that repository. Count contributing Teams across saved Projects, including work in a Project's additional repositories; temporary Workers within a Team do not independently trigger this transition.

Resolve the repository from the actual contribution scope and verified repository identity, not the Project label or Team title. Account for checkout, host, and shared Git/JJ storage when locating the working copies being coordinated. Verify repository provenance when paths differ; similar folder names alone do not establish identity, and forks should not be silently treated as the same repository. Reuse an existing Team with this responsibility even if its display name differs. Keep one active version-control owner for the repository, with explicit checkout contexts when it spans hosts or working copies.

Iris establishes the repository-wide assignment and return destinations, selecting a suitable saved Project as the Team's home without creating one owner per Project. The [Version Control Coordinator](../roles/version-control-coordinator.md) then coordinates local history and review preparation; working Teams continue implementation and testing and push their change handoffs directly to it.

## Transition from one working Team to several

When a second working Team joins, Iris communicates the version-control owner and repository scope to every affected Team, including the original contributor, and to their owning Iris tasks when applicable. Reuse the shared [ownership-change and handoff contracts](assignment-and-return.md#team-ownership-and-return-routing).

Contributors acknowledge the route and report pending changes, validation, readiness, and any version-control operation already underway. Reconcile those operations before transferring history mutation responsibility; treat missing acknowledgment as an unsettled transition rather than assuming the old owner stopped. Continue independent implementation where safe while coordinating a clear handoff of the affected changes.

After the transition, route commit/checkpoint, history restructuring, branch/bookmark, and PR work through the Version Control Team. Contributors retain source editing, testing, and read-only inspection. Agree which files or hunks are ready and coordinate mutations with affected contributors so ongoing edits remain intact. Reconcile competing ownership claims before mutating shared history.

If the Version Control Team becomes unavailable or the number of contributors falls, preserve pending work and agree on an explicit ownership transfer or retirement rather than silently resuming independent history mutations. Team assignment does not itself grant new checkpoint, publication, merge, or deployment authority; carry existing approvals within their scope.
