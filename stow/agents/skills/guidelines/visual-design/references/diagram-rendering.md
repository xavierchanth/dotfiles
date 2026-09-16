# Diagram Editing and Rendering

Use Mermaid when its layout model suits the explanation. Use Excalidraw as the fallback
for freely placed elements. Keep a source file alongside the document's other assets;
PNG is a generated deliverable, not a second editing authority.

## Setup

The renderer lives in `../scripts/diagram-renderer/` relative to this reference folder.
Use the workstation's Node runtime (managed through Mise in this repository).
From the renderer directory, install the locked dependencies and browser once:

```sh
npm ci --ignore-scripts
npm run setup-browser
```

Setup downloads packages and Chromium. Later Excalidraw renders use local package
assets and block external requests; no persistent service or MCP is required.
On Linux, Chromium also requires its platform libraries; use the host's browser
dependency setup if launch reports missing libraries.

## Render

Run from the renderer directory, using absolute source and destination paths:

```sh
node render.mjs /path/to/diagram.mmd /path/to/diagram.png
node render.mjs /path/to/diagram.excalidraw /path/to/diagram.png 3
```

The optional scale defaults to 2. Outputs use a light background suitable for documents
and slides. Regenerate after source edits, inspect the PNG, and embed it at a readable
size. Destination directories must exist. Rendering replaces an existing output PNG.

## Mermaid

Keep `.mmd` text canonical. Preview the same definition in an Obsidian Mermaid block
when useful; treat any copied block as a preview rather than an independently maintained
source. The renderer delegates to Mermaid CLI using the installed Chromium.

## Excalidraw

Use Obsidian's Excalidraw plugin for usual manual editing. The optional workbench
provides a separate browser canvas for live agent collaboration. Transfer drawings
explicitly through import/export when switching editors; they are not automatically
synchronized. Save the current editing session before handing the drawing over.

Keep standard `.excalidraw` JSON canonical. Read the current scene before editing;
preserve element IDs, positions, bindings, groups, app state, and embedded files except
where the requested change affects them. Prefer targeted updates over regenerating
the scene. The renderer normalizes elements through Excalidraw's library and exports PNG.

Obsidian's Excalidraw plugin can use a Markdown wrapper around scene data. This renderer
accepts standard JSON, not `.excalidraw.md`. Export from the plugin to standard
`.excalidraw` before rendering. If the vault wrapper is chosen as the authoring source,
treat the standard JSON as an export and avoid maintaining both independently.
Verify this import/export round trip in the actual vault before adopting it routinely.

For a live shared canvas or element-level tools, read [optional Excalidraw MCP setup](optional/excalidraw-mcp.md).
Keep the file renderer as the default for source-to-PNG work; load the optional setup
only when the user requests it or live editing would materially help.
