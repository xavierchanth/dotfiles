Start with native HTML, CSS, and JavaScript. Add one of these libraries when it materially improves the result.

Versions checked 2026-09-04:

- [Pico CSS](https://picocss.com/docs/classless) `2.1.1` — semantic document, table, and form styling.
- [Observable Plot](https://observablehq.com/plot/) `0.6.17` — charts from prepared tabular data.
- [Mermaid](https://mermaid.js.org/config/usage.html) `11.17.2` — diagrams embedded in a richer webview.

Pico CSS, inside `<head>`:

```html
<link
  rel="stylesheet"
  href="https://cdn.jsdelivr.net/npm/@picocss/pico@2.1.1/css/pico.classless.min.css"
>
```

Observable Plot, with prepared tabular data:

```html
<div id="plot"></div>
<script type="module">
  import * as Plot from "https://cdn.jsdelivr.net/npm/@observablehq/plot@0.6.17/+esm";

  const data = [
    {name: "Alpha", value: 3},
    {name: "Beta", value: 7},
  ];

  document.querySelector("#plot").append(
    Plot.barY(data, {x: "name", y: "value"}).plot({y: {grid: true}}),
  );
</script>
```

Mermaid:

```html
<pre class="mermaid">
flowchart LR
  A[Input] --> B[Output]
</pre>
<script type="module">
  import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11.17.2/dist/mermaid.esm.min.mjs";
  mermaid.initialize({startOnLoad: true, securityLevel: "strict"});
</script>
```

Choose one library per job. Use [notebooks](../notebooks.md) when data preparation or reactive computation is central to the result.

When updating dependencies:

- Check the latest stable release on each linked project page.
- Update the version list and every matching URL together.
- Advance the checked date.
- Open a minimal page for each snippet and verify that it renders.
