# Cage MCP server

`cage-mcp` exposes screenshot-based Computer Use over MCP stdio. The
`cage-desktop` group installs it and registers `mcp_servers.cage` using
`codex mcp add` after mise installs Codex. It is selected on Hades, Poseidon,
and Zeus. Restart the Codex connection after Home Manager activation to discover
the tools. Building the configuration alone does not install or register them.

## Interface

The installed macOS Computer Use plugin's `computer-use` skill documents a
`Sky` interface backed by `@oai/sky`; the newer unified plugin wraps that service
in a JavaScript REPL. This server follows the documented app-scoped method names
and input conventions, using ordinary MCP tools rather than reproducing that
private REPL service.

| Tool | Cage behavior |
| --- | --- |
| `launch_app(executable, args)` | Create a new task-specific session; return its opaque app ID. |
| `list_apps()` | List sessions owned by this MCP connection. |
| `get_app_state(app, disableDiff)` | Return a full PNG image and dimensions; `disableDiff` is accepted without changing behavior. |
| `click(app, x, y, mouse_button, click_count)` | Move and click within the session using one VNC connection. |
| `drag(app, from_x, from_y, to_x, to_y)` | Drag with the left mouse button. |
| `scroll(app, direction, x, y, pages)` | Scroll at the given location; a page approximates eight wheel steps. |
| `press_key(app, key)` | Send an XKB key or chord such as `Return` or `ctrl+a`. |
| `type_text(app, text)` | Type UTF-8 text; newline characters can submit forms. |
| `close_app(app)` | Stop the owned systemd scope and clean up temporary session files. |

An `app` is a session ID returned by this server, not a macOS bundle identifier,
process ID, arbitrary Wayland socket, or TCP endpoint. `get_app_state` does not
implicitly launch an app. The server limits each connection to four sessions.

State results contain native MCP `image` content (`image/png`, base64) plus
structured metadata: app ID, backend, screenshot width/height, original-pixel
coordinate space, and supported capabilities. Images are not resized. There is
no host-local `file://` URL for clients to retrieve across SSH. Input tools return
a fresh screenshot so the client can inspect the result before acting again.

The macOS accessibility tree, diffs, `element_index`, `set_value`, `select_text`,
`perform_secondary_action`, and rich `paste` semantics are not implemented.
Coordinate actions require a previous screenshot and reject out-of-bounds
coordinates. `element_index` requests explicitly fail. This is a compatible
subset of interaction concepts, not a drop-in `@oai/sky` replacement or the
built-in Codex Computer Use plugin.

## Transport and ownership

Codex launches the server locally on the selected host. A client on another
machine can also launch `cage-mcp` via its authorized SSH command as a stdio MCP
server. SSH diagnostics must stay on stderr; do not allocate a TTY for MCP.
No HTTP endpoint or additional firewall opening is configured.

Each session has its own random systemd scope name. The server never attaches
to an existing desktop or accepts a caller-selected port. It stops owned scopes
on `close_app`, startup failure, or MCP disconnect. Unique scope names prevent
cleanup from targeting an unrelated app that later reuses a VNC port.

WayVNC listens on loopback; screenshots use `grim`, pointer actions use `vncdo`,
and keyboard actions use `wtype`. Text travels over stdin instead of becoming
shell syntax. The process runs as its invoking user. Cage is a display boundary,
not an OS sandbox: launching an executable grants it that user's access.

## Validation and sources

`tests/cage-mcp.py` exercises the backend boundaries and a real MCP stdio
initialize/list/call/disconnect exchange with a fake display. The Nix flake
exposes it as `checks.SYSTEM.cage-mcp-protocol`. `tests/cage-session.py` tests
the launcher lifecycle. These tests do not replace a live Wayland smoke test.

Interface reference: installed OpenAI `computer-use` plugin version
`1.0.1000926`, `skills/computer-use/SKILL.md` (`Sky` API), and unified plugin
version `26.901.41600`, its launcher and tool descriptions. No private native
implementation is copied or required.

- [MCP Python SDK v1](https://py.sdk.modelcontextprotocol.io/v1/) — the pinned Nixpkgs provides SDK 1.29.0.
- [WayVNC](https://github.com/any1/wayvnc) — headless Wayland capture and input.
- [VNCDoTool commands](https://vncdotool.readthedocs.io/en/latest/usage.html) — pointer operations.
- [wtype](https://github.com/atx/wtype) — Wayland keyboard input.
