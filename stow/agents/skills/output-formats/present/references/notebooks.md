Use Marimo by default when executable Python, reactive values, data exploration, or meaningful controls are part of the result. Use Jupytext when the user explicitly requests it.

Versions checked 2026-09-04:

- [Marimo](https://docs.marimo.io/) `0.24.0`
- [Jupytext](https://jupytext.readthedocs.io/en/latest/using-cli.html) `1.19.5`

Marimo authoring:

- Store the notebook as a `.py` file with PEP 723 inline dependency metadata.
- Use markdown cells for the narrative and small reactive cells for computation.
- Keep dependencies minimal and make data flow explicit.
- Add controls when they improve exploration.

Create or edit in an isolated UV environment:

```sh
uv run --no-project --with 'marimo==0.24.0' marimo edit --sandbox <file>.py
```

Present it as a headless web app:

```sh
uv run --no-project --with 'marimo==0.24.0' marimo run --sandbox --headless <file>.py
```

Execute it as a script:

```sh
uv run <file>.py
```

Add artifact dependencies with `uv add --script <file>.py <packages>`. Use `uv lock --script <file>.py` when reproducibility requires a lockfile. Verify the notebook runs, then give the user the source file and local URL when applicable. See the [UV integration guide](https://docs.astral.sh/uv/guides/integration/marimo/).

Jupytext operations:

```sh
uv run --no-project --with 'jupytext==1.19.5' jupytext --to py:percent <file>.ipynb
uv run --no-project --with 'jupytext==1.19.5' jupytext --to py:marimo <file>.ipynb
uv run --no-project --with 'jupytext==1.19.5' jupytext --sync <file>.ipynb
```

Use `--test` to verify a round trip when conversion fidelity matters.

When updating dependencies:

- Check the latest stable release on each linked project page.
- Update the version list and every matching command together.
- Advance the checked date.
- Run the authoring or conversion boilerplate and verify its output.
