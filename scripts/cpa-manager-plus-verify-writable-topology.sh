set -euo pipefail
umask 077

data_root=${1:-/data}
canonical_root=${2:-/var/lib/cpa-manager-plus}
probe="$data_root/.cpamp-write-probe.$$"
canonical_probe="$canonical_root/$(basename "$probe")"
trap 'rm -f "$probe" "$canonical_probe"' EXIT

printf 'state-topology-probe\n' > "$probe"
test -f "$canonical_probe"
test "$(stat -c '%d:%i' "$probe")" = "$(stat -c '%d:%i' "$canonical_probe")"

rm -f "$probe"
trap - EXIT
