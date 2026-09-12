---
name: prompting-guidelines
description: Author or revise durable instructions for AI agents, including skills, system prompts, and AGENTS.md files. Use when designing agent behavior through reusable instructions, rather than composing ordinary conversational requests.
---

# Prompting Guidelines

Write instructions that develop useful judgment. Give the agent enough
direction to make appropriate decisions in situations the author has not
explicitly anticipated.

## Establish the Behavioral Goal

Identify when the instructions apply, what behavior they should influence,
and what successful work looks like. Preserve the user's intended scope.

Include guidance that changes decisions or improves outcomes. Keep each
instruction focused on a distinct contribution.

When authoring a skill, use the available skill-creator guidance for its
structure, discovery metadata, resources, and validation.

## Describe the Desired Behavior

Lead with what the agent should do. Explain the underlying principle when
it helps the agent apply the instruction beyond the immediate example.

For matters of taste, frequency, or degree, describe the preferred balance
and the conditions that justify a different choice.

For example:

> Express simple relationships through proximity, spacing, and alignment.
> Use containers when they clarify grouping, state, or interaction.

This gives the agent a useful starting point and a reason to depart from it.

Reserve prohibitions for actual boundaries: cases where the prohibited
behavior is itself a failure. State preferences as preferences.

## Give Decisions a Useful Shape

When judgment matters, connect the desired outcome to:

- A suitable default.
- The conditions that make another approach appropriate.
- Criteria for evaluating the result.

Express preferences as ordering where that helps: start with an approach
that usually works, then introduce additional structure or complexity when
it serves a concrete purpose.

Treat this as a way to clarify decisions, adapting the form and level of
detail to the instruction.

## Preserve Degrees of Freedom

Constrain what determines success and leave other choices open.

Use precise procedures where correctness depends on a particular sequence.
Use principles and decision criteria where the task benefits from
interpretation, experimentation, or taste.

Keep scope and authorization explicit where they affect the work. A
workflow should operate within the user's request.

## Use Examples to Calibrate

Choose examples that reveal why a decision works. Explain which part of
the example carries the principle.

When a default could become an accidental rule, include a contrasting
case that shows when another choice is appropriate.

Keep examples proportional to their value. A clear principle may need
only one example, or none.

## Evaluate the Outcome

For work requiring judgment, provide a proportionate loop: produce,
inspect, and refine. Give the agent criteria for examining the result
itself.

Review the instructions against realistic situations:

- Does the agent understand what successful work requires?
- Can it recognize when the default is unsuitable?
- Are requirements distinguishable from preferences?
- Could literal compliance produce repetitive or inappropriate results?
- Does the process introduce work that contributes little to the outcome?

Refine instructions around the cause of a problem. Prefer improving the
principle or decision criteria over accumulating rules for individual
incidents.
