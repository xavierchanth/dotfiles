---
name: nix-management
description: Inspect, change, and validate Nix flakes, NixOS and nix-darwin modules, Home Manager configurations, packages, overlays, dev shells, and pinned inputs.
---

# Nix Management

Make focused, reproducible changes and establish what the affected outputs actually validate. Follow repository instructions for local structure, update policy, and deployment.

## Find ownership and scope

Start with local file discovery using `rg --files` and targeted searches for flake outputs and module imports. Trace the requested behavior from its owning module to the consuming hosts, users, profiles, or packages. Adapt to the existing entrypoints when the repository does not use flakes.

Prefer repository recipes and scripts after reading their implementation and relevant callees. Classify them by their actual effects: a command named `build` may activate a configuration, and an update wrapper may also deploy. Carry forward the user's existing authorization; command names alone do not establish scope.

## Make the change

- Extend the nearest owning module and preserve local style. Keep unrelated configuration, formatting, and input pins outside the edit.
- Derive package executables and contextual paths from Nix values, such as `${pkgs.tmux}/bin/tmux` and `${config.home.homeDirectory}`.
- Check option and package availability against the pinned inputs. Use their source or version-matched documentation when a rename, type, or platform constraint is uncertain.
- Resolve module ownership and merge semantics before introducing overrides. Use priorities such as `mkDefault` or `mkForce` when they express intended policy, rather than merely suppressing a conflict.

## Validate the affected behavior

Choose evidence proportional to the change:

- **Evaluation** checks relevant expressions and configuration structure; select attributes that force the changed behavior to evaluate.
- **Builds and checks** establish that selected derivations can be realized and relevant tests pass. A successful flake check does not prove every host configuration builds.
- **Activation and runtime checks** establish live behavior when applying the change is part of the user's request. Activation is a separate task action, not an automatic escalation from validation.

For shared changes, select affected configurations that cover meaningful platform and profile differences. Broaden checks when the change or a failure warrants it, and complete repository-required validation. Distinguish evaluation on other systems from builds that need a compatible builder.

Preserve locked inputs during ordinary validation. Dependency updates require a requested input change; live activation, deployment, and boot-generation changes require authorization to apply. An already-authorized apply request does not need another confirmation merely because validation finished.

Read [references/workflows.md](references/workflows.md) when selecting commands, updating inputs, or diagnosing evaluation and build failures.

## Assess the result

Trace failures to the relevant expression or build log before editing again. Separate configuration defects from unavailable credentials, builders, downloads, or other environment limitations.

Report the behavior changed, the outputs evaluated or built, whether anything was activated, and material gaps in coverage. Describe runtime-only uncertainty as such rather than implying a build proves live behavior.
