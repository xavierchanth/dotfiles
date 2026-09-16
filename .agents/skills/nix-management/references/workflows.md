# Nix Management Workflows

## Discover the relevant outputs

Start with local inspection before evaluating the flake:

```sh
rg --files . | rg '(^|/)(flake\.lock|.*\.nix)$'
rg -n --glob '*.nix' 'darwinConfigurations|nixosConfigurations|homeConfigurations|devShells|packages|checks|overlays' .
```

Follow imports, profile composition, and host inventory to determine consumers. Read repository recipes and their callees before choosing them, including default targets and any activation after an update.

If output names remain unclear, `nix flake show --no-update-lock-file` can help, but may evaluate substantial parts of the flake. Use exact discovered output names in commands below; placeholders are illustrative.

## Choose validation

| Change | Useful evidence |
| --- | --- |
| Module option or service configuration | Evaluate the affected value and configuration derivation; build the affected host when integration matters |
| Shared module or profile composition | Evaluate representative consumers across affected platforms/profiles; build relevant configurations and checks |
| Package or overlay | Build the affected package; include a consuming configuration when package integration changed |
| Dev shell | Run a bounded command in the selected shell that exercises the changed tool or environment |
| Flake output wiring | Evaluate the affected outputs and run applicable flake checks |
| Pinned input | Inspect lock changes, then validate affected consumers and repository-required checks |

Evaluation is lazy: querying a host's platform alone does not validate its changed service configuration. Select the relevant option, configuration derivation, or existing assertion/check.

### Evaluation and checks

```sh
nix eval --no-update-lock-file '.#nixosConfigurations.<host>.config.services.openssh.enable'
nix eval --raw --no-update-lock-file '.#nixosConfigurations.<host>.config.system.build.toplevel.drvPath'
nix flake check --no-build --no-update-lock-file
nix flake check --all-systems --no-build --no-update-lock-file
nix flake check --no-update-lock-file
```

The final command also builds applicable checks. `--all-systems --no-build` broadens evaluation without asking to build every system's checks; evaluation may still fetch inputs or require builds for import-from-derivation. Flake checking handles recognized output types, so explicitly validate relevant custom outputs and host configurations as needed.

### Targeted builds without activation

```sh
nix build --no-link --no-update-lock-file '.#packages.<system>.<name>'
nix build --no-link --no-update-lock-file '.#checks.<system>.<name>'
nix build --no-link --no-update-lock-file '.#homeConfigurations.<name>.activationPackage'
nix build --no-link --no-update-lock-file '.#darwinConfigurations.<host>.system'
nix build --no-link --no-update-lock-file '.#nixosConfigurations.<host>.config.system.build.toplevel'
```

Use discovered output paths and a compatible local or configured remote builder. `--no-link` avoids creating a result symlink; omit it when that artifact is useful. Prefer inspected repository wrappers when they implement the requested operation. Build commands generally do not need elevation merely because the eventual activation does.

### Dev shells

```sh
nix develop --no-update-lock-file '.#<shell>' -c sh -c 'command -v <tool>'
nix develop --no-update-lock-file '.#<shell>' -c <tool> --version
```

Choose a command that exercises the actual change; tool presence alone may be insufficient. Inspect relevant shell hooks, since entering a development environment can run repository code.

## Preserve or update inputs deliberately

During validation, prefer `--no-update-lock-file` to fail if lock changes would be needed. `--no-write-lock-file` only prevents saving a changed lock; it can still allow evaluation against an updated in-memory lock. If the task intentionally adds or changes an input declaration, generate the corresponding lock change as part of that work.

For requested dependency updates:

- Follow the repository's update policy and inspect wrappers for additional effects, particularly activation and broad input updates.
- Select the smallest requested set of inputs. On modern Nix, `nix flake update <input>` updates a named input; check the installed command's help if version compatibility is uncertain.
- Inspect direct and transitive lock changes for unexpected scope, and validate their affected consumers.

A requested update does not by itself authorize a wrapper's subsequent activation. Use its supported update-only mode when appropriate.

## Apply when requested

Use the repository's deployment or activation workflow after relevant validation. Confirm the actual target and mode from the request and configuration. Modes such as `switch`, NixOS `test`, `boot`, and remote deployment have different live or next-boot effects; choose the one that implements the requested outcome.

When runtime verification is needed, check the affected service or behavior after the authorized apply. If activation is outside scope, report the remaining runtime uncertainty.

## Diagnose failures

- **Missing source file:** Check that the path exists and is included in the flake's source. Git-backed flakes can omit untracked files; follow the repository's version-control workflow rather than silently changing source semantics with a different URL scheme.
- **Missing attribute or option:** Verify the output name, system key, imports, and pinned package/module version.
- **Option conflict or type error:** Inspect definition locations, option types, and merge priorities. Correct unintended duplicate ownership before reaching for `mkForce`.
- **Infinite recursion:** Trace dependencies through `config`, module arguments, and overlay `final`/`prev`; reduce the failing expression to locate the cycle.
- **Build failure:** Read the failing derivation's log and separate package compilation or tests from fetch, credential, disk, or builder failures.

Use a focused trace when the normal error lacks enough context. Preserve pins and evaluation purity while diagnosing; changing inputs or adding `--impure` should follow the intended fix, not serve as a generic error workaround.
