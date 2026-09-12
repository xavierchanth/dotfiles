## Harness controls

Use the active installation’s documented agent, model, and reasoning controls where available. Prefer isolated critic and verifier context when supported, and resume correction reviews when agent continuation is available. Resolve the profiles below through the exposed model identifiers or documented aliases; do not assume another harness’s parameter names or capabilities.

## Profiles

| Profile | Small | Normal | Large |
|---|---|---|---|
| `coordinator` | `gpt-5.6-sol:low` | `gpt-6-astra:low` | `gpt-6-astra:medium` |
| `general` | `gpt-5.6-sol:low` | `gpt-5.6-sol:low` | `gpt-6-astra:low` |
| `design` | `gpt-5.6-sol:low` | `gpt-6-astra:low` | `gpt-6-astra:medium` |
| `design-with-critique` | `gpt-5.6-sol:low` | `gpt-5.6-sol:low` | `gpt-5.6-sol:medium` |
| `critique` | `gpt-6-astra:low` | `gpt-6-astra:low` | `gpt-6-astra:medium` |
| `implement` | `gpt-5.6-sol:low` | `gpt-5.6-sol:low` | `gpt-5.6-sol:medium` |
| `verify` | `gpt-6-astra:low` | `gpt-6-astra:low` | `gpt-6-astra:medium` |
| `researcher` | `gpt-5.6-terra:high` | `gpt-5.6-sol:low` | `gpt-5.6-sol:medium` |
| `explorer` | `gpt-5.6-luna:high` | `gpt-5.6-sol:low` | `gpt-5.6-sol:low` |

Cells use `model:reasoning`. Normal is the default and uses the row name; Small and Large append `-small` and `-large`. `design-with-critique` selects the designer's profile when critique is selected upfront; it is not an additional agent or stage. The separate `flash` shortcut uses `gpt-5.6-luna:high` for tiny assignments at every size.

Apply group-wide and targeted size selections using SKILL.md. Resolve unavailable models through its fallback guidance. The user-facing coordinator's model is selected by the user in the harness. Delegated coordination uses the `coordinator` profile, subject to explicit user model and reasoning selections.
