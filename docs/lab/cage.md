# Cage sessions

Hades, Poseidon, and Zeus select the `cage-desktop` group. It supplies on-demand
headless Cage sessions, WayVNC, screenshots (`grim`), keyboard input (`wtype`),
and mouse input (`vncdo`). The `cage-session` skill is installed into the managed
user's `.codex/skills` only on hosts selecting this group.

Codex uses the [Cage MCP server](cage-mcp.md) for app-scoped tools and inline
screenshots. The CLI below remains available for manual sessions; MCP owns
separate sessions and does not attach to manually started ones.

There is no display manager or always-running graphical session. The app is
chosen when starting a task:

```sh
cage-session -- firefox --no-remote
cage-session --port 5901 -- another-app argument
```

Run from an SSH login as the task user; use tmux when the session should survive
disconnection. Each port names a systemd user scope (`cage-session-5900.scope`).
Concurrent sessions need different ports and application profiles when the app
normally reuses an existing process. Applications retain their usual user data.

The command prints its Wayland display and loopback VNC endpoint. Use those
values for screenshots and input. A human viewer can forward the port with
`ssh -N -L 5901:127.0.0.1:5900 HOST` and connect a VNC client to localhost:5901.
VNC authentication is disabled on the loopback listener; the SSH tunnel provides
remote authentication and encryption. Use a VNC client that supports this mode.
No VNC or RDP port is opened in the firewall.

Close the application when done and stop its scope if any processes remain:

```sh
systemctl --user stop cage-session-5900.scope
```

The session runs as its invoking user. Cage limits the visible application,
not its filesystem permissions. The `computer` account remains available, but
the launcher does not switch users or grant privilege. Rendering uses a software
headless backend so no display, GPU seat, or GNOME login is required.

Deploy health checks cover the base machine services. On-demand Cage scopes
are intentionally absent from the required-units manifest. The configuration
replaces the former GNOME/GDM setup and its RDP listener after deployment.
