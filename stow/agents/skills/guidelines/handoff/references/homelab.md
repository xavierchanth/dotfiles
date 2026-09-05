# Homelab names

| Machine | Platform | Kind | Profile |
| --- | --- | --- | --- |
| charon | — | openwrt | openwrt-router |
| eris | aarch64-darwin | darwin | darwin-server |
| hades | x86_64-linux | nixos | linux-server |
| nyx | aarch64-darwin | darwin | darwin-workstation |
| poseidon | x86_64-linux | nixos | linux-server |
| zeus | x86_64-linux | nixos | linux-server |

Match a requested machine name to this table, then resolve its connection through the active harness. Inventory names are not harness host IDs.

Charon is a router, not a default agent execution destination. Profiles describe configured roles; verify tools and capacity only as needed for the assignment.

Resolve "here" from the caller's current machine. Resolve destination repository paths through the harness; source paths need not exist there.

Use live connection details for reachability and routing. If the requested machine is absent or unavailable, report the missing connection. This reference does not require access to the dotfiles repository, SSH configuration, or lab runbooks.
