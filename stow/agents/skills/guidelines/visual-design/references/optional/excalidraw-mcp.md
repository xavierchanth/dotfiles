# Optional Excalidraw Workbench

Use when live manual/agent editing, targeted element operations, or visual iteration
would help. Keep ordinary file rendering independent of this optional integration.
Suggest setup when useful; enable it when the user wants the integration.

## Setup

The [workbench](https://github.com/yctimlin/mcp_excalidraw) offers CLI and MCP access.
The documented baseline is version 2.0.0 with Node 20 or newer. Its local canvas
starts automatically and normally uses `http://127.0.0.1:3000`.

For a trial without persistent MCP configuration:

```sh
npx -y mcp-excalidraw-server@2.0.0 start
npx -y mcp-excalidraw-server@2.0.0 status
```

Open the canvas URL in a browser; image capture requires the tab.
For MCP, register this stdio process using the client's supported configuration:

```json
{
  "command": "npx",
  "args": ["-y", "mcp-excalidraw-server@2.0.0"]
}
```

The first launch downloads the package. Keep the local bind address. Export the scene
before stopping; live state is in memory. The optional sharing operation uploads data.

```sh
npx -y mcp-excalidraw-server@2.0.0 export --out diagram.excalidraw
npx -y mcp-excalidraw-server@2.0.0 stop
```

## Integrate with This Workflow

The workbench is a separate browser editing surface, not an Obsidian integration.
Use Obsidian for usual manual editing and the workbench when live agent collaboration
is useful. Import the latest saved drawing when switching to the workbench and export
it before returning to Obsidian. Keep one canonical source and avoid concurrent edits
to independent copies; there is no automatic synchronization between these editors.

Inspect the existing client configuration before changing it. Preserve unrelated
servers and follow this repository's managed configuration conventions. Keep the
version explicit; review a newer release before changing the pin. A separate upstream
skill installation is unnecessary for this setup.

Before changing an occupied canvas, establish which drawing it contains and save its
current work. Use a disposable scene to verify tool discovery, manual and agent edits,
export, and PNG rendering. Then import the intended source and make targeted changes.

Export back to the chosen canonical source after editing. Use the local renderer from
[diagram rendering](../diagram-rendering.md) for document PNGs. Read MCP file-export
scope from the installed server's configuration and set it to the intended artifact
directory when needed.

To remove the integration, export outstanding work, stop the canvas, and remove only
its client registration. These are setup instructions, not a claim that this optional
server has been installed or tested on the current machine.
