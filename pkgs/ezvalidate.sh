#!/usr/bin/env bash
# Usage: ezvalidate [--flake DIR] [HOST...]
# Evaluates each NixOS configuration of the flake (DIR, /etc/nixos unless
# given) down to its system's derivation, without building anything. With no
# HOST it checks every one under nixosConfigurations, so nobody has to know
# the name. A wrong option name, a type error, a missing file or a failed
# assertion shows here in seconds, instead of after the disk is partitioned.
FLAKE=/etc/nixos
HOSTS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --flake)
      FLAKE="$2"
      shift 2
      ;;
    *)
      HOSTS+=("$1")
      shift
      ;;
  esac
done

if [ ! -f "$FLAKE/flake.nix" ]; then
  echo "No flake.nix in $FLAKE - nothing to check." >&2
  exit 1
fi

# --impure as in ezinstall, so a setup that evaluates here evaluates there.
if [ "${#HOSTS[@]}" -eq 0 ]; then
  if ! NAMES=$(nix eval --json "$FLAKE#nixosConfigurations" \
    --apply builtins.attrNames --impure); then
    echo "$FLAKE/flake.nix does not evaluate (see above)." >&2
    exit 1
  fi
  mapfile -t HOSTS < <(jq -r '.[]' <<<"$NAMES")
fi
if [ "${#HOSTS[@]}" -eq 0 ]; then
  echo "No nixosConfigurations in $FLAKE/flake.nix." >&2
  exit 1
fi

FAILED=0
for h in "${HOSTS[@]}"; do
  echo "Checking \"$h\"..."
  if nix eval --raw --impure \
    "$FLAKE#nixosConfigurations.\"$h\".config.system.build.toplevel.drvPath" >/dev/null; then
    echo "\"$h\" is valid."
  else
    echo "\"$h\" does not evaluate (see above)." >&2
    FAILED=1
  fi
done
exit "$FAILED"
