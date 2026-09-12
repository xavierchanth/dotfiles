#!/usr/bin/env bash
# Negated probes are assertions under errexit.
# shellcheck disable=SC2251
set -Eeuo pipefail
root=${TEST_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
lab_update=${LAB_UPDATE_BIN:-$root/bin/shared/lab-update}
out=$(LAB_UPDATE_TARGET=hades LAB_UPDATE_SSH_USER=chant LAB_UPDATE_IDENTITY=- LAB_UPDATE_PROXY_JUMP=- "$lab_update" --dry-run hades)
grep -Fq 'no SSH or network calls' <<<"$out"
grep -Fq 'transport: chant@hades' <<<"$out"
dedicated=$(LAB_UPDATE_TARGET=hades LAB_UPDATE_SSH_USER=deploy LAB_UPDATE_IDENTITY=.ssh/id_ed25519_dotfiles_deploy LAB_UPDATE_PROXY_JUMP=- "$root/bin/shared/lab-update" --dry-run hades)
grep -Fq 'transport: deploy@hades' <<<"$dedicated"
raw_out=$(mktemp); raw_err=$(mktemp); trap 'rm -f "$raw_out" "$raw_err"' EXIT
if env -u LAB_UPDATE_TARGET -u LAB_UPDATE_SSH_USER -u LAB_UPDATE_IDENTITY -u LAB_UPDATE_PROXY_JUMP "$root/bin/shared/lab-update" --dry-run hades >"$raw_out" 2>"$raw_err"; then exit 1; fi
grep -q 'packaged flake app' "$raw_err"
rm -f "$raw_out" "$raw_err"; trap - EXIT
# Evaluate rendered contracts without building or contacting a network.
for host in hades poseidon; do
  var="${host^^}_MANIFEST"
  manifest=${!var:-$(nix eval --offline --no-write-lock-file --raw "$root#nixosConfigurations.$host.config.environment.etc.\"lab-update/required-units\".text")}
  [[ -n $manifest ]]
  ! grep -q '^$' <<<"${manifest%$'\n'}"
  grep -Fqx NetworkManager.service <<<"$manifest"
  grep -Fqx sshd.service <<<"$manifest"
  grep -Fqx tailscaled.service <<<"$manifest"
  ! grep -Fqx display-manager.service <<<"$manifest"
done
# Exercise the driver's canonical manifest contract with immutable-style symlinks.
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
validate() { local link=$1 canonical u; canonical=$(readlink -f -- "$link") || return 1; [[ -f $canonical && -r $canonical ]] || return 1; local n=0; while IFS= read -r u || [[ -n $u ]]; do [[ -n $u && $u =~ ^[A-Za-z0-9@_.:-]+\.service$ ]] || return 1; ((++n)); done <"$canonical"; ((n)); }
printf 'sshd.service\n' >"$t/store-file"; ln -s "$t/store-file" "$t/manifest"; validate "$t/manifest"
printf 'sshd.service\n\n' >"$t/store-file"; ! validate "$t/manifest"
printf 'not a unit\n' >"$t/store-file"; ! validate "$t/manifest"
echo 'lab-update tests passed'
