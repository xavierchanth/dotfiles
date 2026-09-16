# Codex

## Setup and discovery

- Discover available tools and read their current contracts. Desktop app capabilities are not necessarily available in the CLI or another harness.
- Use `list_threads`, `read_thread`, and `list_projects` to resolve the task, current host, and destination project. Identify tasks using their exact returned titles.
- Match the user's machine name to a returned host ID. Do not construct a host ID from its hostname or SSH alias.
- Cross-host handoff requires a connected host and a saved project for the same Git repository. If the project is a repository subdirectory, save the same subdirectory on both hosts.
- For a missing SSH connection, follow the [remote setup procedure](https://learn.chatgpt.com/docs/remote-connections#connect-to-an-ssh-host): configure a concrete SSH alias, establish connectivity, install/authenticate Codex on the host, then enable it under Settings → Connections and save the remote project.
- When setting up a missing connection, verify that `codex` is available in the remote login shell and authenticated.
- Provision required runtimes, dependencies, credentials, and any assignment-specific extensions through the existing environment setup. Handoff does not copy the entire development environment.

## Send and return

- Use `handoff_thread` with the resolved task ID and destination host ID. Omitting the host currently toggles between checkout and worktree on the same machine; it does not mean "return here".
- The current tool can move another task, interrupts a running task before transfer, and excludes Codex cloud destinations.
- For the calling task, explain the app's location-selector action or use an already authorized separate controlling task. Do not create a controller task without authorization.
- Use `get_handoff_status` with the returned operation ID, latest revision, and bounded wait. Reconcile ambiguous responses using that ID before retrying.
- Supply `followUpPrompt` when the assignment should continue after the move; verify the resulting execution state.
- For an explicitly requested independent task, use `create_thread` or an appropriate `fork_thread`. A fork includes completed history only, not the unfinished active turn.
- Honor project and starting-state contracts. If the requested remote target or working state cannot be expressed, resolve the limitation before creating work elsewhere.
- Use `wait_threads` with returned cursors, `read_thread` for inspection, and `send_message_to_thread` for guidance. Track the task's current host.
- Return through another validated handoff to the resolved local host and project. Confirm both transfer completion and the resulting checkout/worktree.

## Working changes and workspace compatibility

- Codex creates or reuses a Git worktree and transfers the task and Git state. A commit is not a general prerequisite for transferring uncommitted changes.
- Verify new, untracked files at the destination when the assignment depends on them. Do not infer their coverage solely from the phrase "Git state".
- Ignored files are not generally transferred. `.worktreeinclude` is documented for local Codex-managed worktrees, not remote worktrees.
- Let Codex manage its own Git worktree paths. A Git worktree is not automatically a JJ workspace.
- Before relying on JJ support, validate the actual source layout, transferred content/revision, and usable destination state in a scoped trial. A colocated Git/JJ root and an additional JJ workspace can expose different Git layouts.
- Report unverified preservation of JJ change IDs, mutable history, and workspace metadata. Do not silently copy `.jj` or initialize a replacement JJ repository as a workaround.
- Check the returned changes before integrating them into another checkout; a handoff may itself change branches or checkout state.

## References

- [Remote connections and cross-host handoff](https://learn.chatgpt.com/docs/remote-connections).
- [Worktrees, uncommitted changes, and ignored files](https://learn.chatgpt.com/docs/environments/git-worktrees).
- Recheck installed contracts and current documentation when behavior changes.
