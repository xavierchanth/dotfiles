# Jio configuration

The `jio` group installs the private Jio flake package and GitHub CLI, and generates portable configuration for Nyx, Eris, Hades, Poseidon, and Zeus. Their existing Mise group manages Codex. Nike remains outside this Nix configuration.

## Prepare the pinned private release

These repository helpers require `nix`, `gh`, and `python3` on PATH. The Jio group supplies GitHub CLI and Python after activation; make them available yourself for the initial bootstrap. Sign into GitHub CLI, then prepare and import the release for the target system before building configuration:

```sh
./scripts/jio-release prepare --system aarch64-darwin
./scripts/jio-release import --system aarch64-darwin
./scripts/nix-with-github build '.#homeConfigurations."chant@nyx".activationPackage' --no-link
```

These commands build configuration without activating it. Select `aarch64-linux` or `x86_64-linux` explicitly when preparing another target; omitting `--system` selects the local Nix system. The helper evaluates the package output and derivation from the exact locked Jio GitHub revision, downloads its `nix-<full-revision>` private release, validates the archive and closure metadata, and imports signed store paths. Jio and its adjacent signing helper keep their runtime dependencies intact. Missing, mismatched, corrupt, or untrusted releases fail without compiling Jio. Ordinary Nix commands remain available for development; run both release steps before configuration builds to avoid a source-build fallback there.

Downloads use the existing `gh` login. Prepared assets and a lock-bound receipt live in a private directory under `$XDG_CACHE_HOME/jio/releases` (default `~/.cache/jio/releases`). Repeating `prepare` validates and reuses an existing release. `import` rechecks the current lock, receipt, metadata, checksum, archive paths, and closure before asking Nix to verify signatures. Neither step writes credentials. To discard an invalid prepared download, remove only the exact cache directory named for its repository, revision, and system, then prepare again.

`nix-with-github` remains the authentication-only wrapper for source fetching and explicit lock updates. It obtains the GitHub CLI token for that invocation and preserves unrelated Nix settings and credentials. Repository-scoped token entries remain authoritative. Tokens are never written to the flake, lockfile, release cache, or generated configuration.

## Initial signing-key trust

The Jio system group adds `nix/modules/shared/jio/cache-public-key` to Nix's trusted public keys on NixOS and macOS, preserving existing keys and user permissions. The matching private signing key stays in the private repository's GitHub Actions secret. Download authentication and store-signature verification are separate checks.

An existing daemon must trust the public key before an ordinary import succeeds. Adding it to these files does not change the running daemon. During a separately authorized initial activation, an operator can activate trust first, or perform a one-time privileged signed import with the reviewed public key explicitly supplied:

```sh
JIO_PREPARED=$(./scripts/jio-release prepare --system aarch64-darwin)
JIO_CACHE=$(mktemp -d)
tar -xzf "$JIO_PREPARED/jio-aarch64-darwin.tar.gz" -C "$JIO_CACHE"
JIO_OUTPUT=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["storePath"])' "$JIO_PREPARED/receipt.json")
sudo nix copy --from "file://$JIO_CACHE" --option require-sigs true \
  --extra-trusted-public-keys "$(cat nix/modules/shared/jio/cache-public-key)" \
  "$JIO_OUTPUT"
```

Run from the dotfiles root and select the same target system in the preparation command and archive filename. `prepare` verifies the archive before this manual extraction. Remove the temporary directory named by `JIO_CACHE` afterward. Keep signature checking enabled. The helper never runs this privileged command or activates a configuration automatically. After the Jio system group is activated, ordinary imports need no additional trusted users or substituter entries. Standalone Home Manager users need their system administrator to configure the public key.

The optional `import --to-store 'local?root=/private/tmp/example'` destination is for disposable-store checks; it does not install into the system store. On macOS, isolated store roots must avoid symlinked parents such as `/tmp`.

Jio source and programs enter the local Nix store. Keep their source and closures out of public caches. Public dotfiles contain only references, portable configuration, and the non-secret signing public key.

## Portable configuration

Home Manager owns `$XDG_CONFIG_HOME/jio/config.toml` and `projects.toml`. Defaults define the `codex`, `github`, and `github-signing` profiles, the `personal` account group, and required SSH Ed25519 signing. No project is selected automatically.

Set `dotfiles.jio.projects` in a shared Home Manager module to declare projects, for example:

```nix
dotfiles.jio.projects = [ {
  id = "example";
  upstream = "https://github.com/example/project.git";
  default_branch = "main";
  account_group = "personal";
  availability = "all-personal-machines";
} ];
```

`dotfiles.jio.settings` exposes the portable settings. Keep tokens, local executable paths, node identities, account IDs, and key material out of both options. Local account and runtime bindings remain under the state directory.

The installed `jio` command is a wrapper around the packaged executable. It supplies the Home Manager configuration/data/state directories, and uses the state's `jio/runtime` directory consistently for interactive commands and services. Its PATH includes Git, GitHub CLI, OpenSSH, and the existing Mise shims. It does not log in or change account bindings.

## Local onboarding and services

On each machine, sign into GitHub CLI and the chosen harness, then use `jio setup-github` and `jio setup-runtime` with explicit account/profile choices. Runtime setup records the actual executable and login home; include an explicit executable search path for the agent's tools. This is a deliberate local operation, not a Nix activation step.

The separate `jio-service` group defines a systemd user service on Linux or a launchd agent on macOS. It is not selected on any host by default. Add it to that host's groups only after onboarding; the `jio` group must also be selected. It uses the same command and directories as interactive Jio. Do not also run Jio's copy-based installer against these managed files.

Linux signing requires a working, unlocked Secret Service store. The configuration does not install an automatic unlock mechanism or promise startup before user login. Choose that lifecycle before enabling unattended work. Enabling a user service does not itself provide a logged-in harness or unlocked credentials.

Stop Jio before refreshing account/runtime bindings after tool upgrades. Those bindings resolve executable paths, so retain old Nix generations and Mise tool installations until rebinding succeeds. Rollback also requires checking which executable versions the local bindings name. Updating the portable configuration must not overwrite local state.

## Checks

Jio's upstream Nix package supplies portable command paths for its isolated control-test fixtures. Dotfiles consumes that exact package without an override so its output matches the signed CI release.

`checks.<system>.jio-release` exercises release identity, checksums, archive safety, closure completeness, and failure behavior with fixtures and mocked commands. Signature acceptance/rejection is additionally checked against disposable Nix stores during release-helper development.

`checks.<system>.jio-config` checks host coverage and isolated default/custom-project/service fixtures, then parses generated TOML with Jio in temporary directories. `checks.<system>.jio-fetch-auth` tests authentication plumbing using fake commands and tokens only. Native service, account, harness, and transport validation is performed separately with the operator; no rebuild switch or deployment is part of these checks.
