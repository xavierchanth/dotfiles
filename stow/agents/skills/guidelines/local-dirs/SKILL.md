---
name: local-dirs
description: Use when placing agent-authored notes, temporary files, or output artifacts in a repository.
---

Use repository-local directories by purpose:

- `scratch/` — notes, plans, and working documents.
- `outputs/` — finished agent-authored artifacts.
- `tmp/` — disposable intermediate files.

Use the directory that matches the artifact. Ensure each directory's `.gitignore` includes:

```gitignore
**
```
