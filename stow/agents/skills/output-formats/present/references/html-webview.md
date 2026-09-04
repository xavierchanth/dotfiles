Create an HTML webview when composition, navigation, styling, charts, or browser-side interaction materially improves the result.

- Prefer a single semantic `.html` file with inline CSS and small inline JavaScript.
- Keep the webview build-free and load the few required dependencies from pinned CDN URLs.
- Use native HTML, CSS, and JavaScript for offline artifacts.
- Read [lists and tables](lists-and-tables.md) when structured collections carry the meaning.
- Read [graphs and hierarchy](graphs-and-hierarchy.md) when relationships carry the meaning.
- Read [HTML libraries](html/libraries.md) before adding a CDN dependency.

Open the file directly when possible. If it requires a server, run:

```sh
uv run --no-project python -m http.server <port> --directory <directory>
```

Preview the result and give the user the file and local URL when applicable.
