# Explanations and Diagrams

Establish what the audience should understand or be able to do and what they already
know. Introduce concepts in a useful dependency order and keep terminology consistent.

Choose the level of abstraction deliberately. Connect concepts to concrete examples,
then show how the example supports the more general understanding. Separate detail
needed now from depth that can be supplied later or alongside the main explanation.

## Diagram Intent

For each proposed diagram, establish:

- The question it answers and its contribution to the surrounding content.
- The necessary entities, relationships, direction, or sequence.
- The abstraction level and meaning of important labels.
- What the audience should notice or understand afterward.
- What belongs in another diagram or supporting explanation.

Keep the brief semantic: visual composition is a separate design responsibility.
Pair the diagram with enough text to orient the reader without duplicating every mark.

## Editable Source

For reusable diagrams, prefer an editable source that the user and an agent can both
maintain, with exports embedded in destination artifacts. Select the tool according
to manual editing, agent editing, layout flexibility, portability, and export needs.
Use Mermaid where structured layouts fit, with Excalidraw as the freeform fallback.
The visual-design skill supplies rendering and source-editing guidance when available.

Use text-based diagrams where their constraints suit the explanation. For diagrams
needing freer composition, preserve a suitable editable source rather than treating
the presentation file or exported image as the only maintained representation.
