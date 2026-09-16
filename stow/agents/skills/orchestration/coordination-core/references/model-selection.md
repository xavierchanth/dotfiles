# Model selection

Default delegated coordinators, roles, and supporting agents to `gpt-5.6-sol` with `low` reasoning. Override when Xavier requests it or a concrete assignment need justifies another available model or effort. State the override briefly and preserve it within its scope.

Aliases: `astra` = `gpt-6-astra`, `sol` = `gpt-5.6-sol`, `terra` = `gpt-5.6-terra`, and `luna` = `gpt-5.6-luna`; omitted reasoning means `low`.

Supporting roles do not inherit model or reasoning overrides from the agent that delegates to them unless that inheritance is explicitly requested. Select each supporting role independently.

When Xavier explicitly requests an unavailable model or reasoning capability, ask how to proceed with that assignment. Otherwise use a user-established equivalent or the configured default and state the fallback briefly.
