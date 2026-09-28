#!/usr/bin/env bash
if ! mountpoint -q /mnt; then
  echo "Nothing mounted at /mnt - partition and mount your target disk there first (e.g. with disko, or manually)." >&2
  exit 1
fi

# Figure out flake-vs-classic (and, for a flake, the host) up front, since
# nixos-install needs it anyway.
if [ -f /etc/nixos/flake.nix ]; then
  echo "flake.nix found - installing via flake."

  mapfile -t HOSTS < <(nix eval --json /etc/nixos#nixosConfigurations \
    --apply builtins.attrNames --impure 2>/dev/null | jq -r '.[]')

  if [ "${#HOSTS[@]}" -eq 0 ]; then
    echo "No nixosConfigurations found in /etc/nixos/flake.nix - check it evaluates." >&2
    exit 1
  elif [ "${#HOSTS[@]}" -eq 1 ]; then
    HOSTNAME="${HOSTS[0]}"
  else
    echo "Multiple hosts defined:"
    select h in "${HOSTS[@]}"; do
      [ -n "$h" ] && HOSTNAME="$h" && break
    done
  fi
elif [ -f /etc/nixos/configuration.nix ]; then
  echo "No flake.nix - installing from /etc/nixos/configuration.nix..."
else
  echo "Neither /etc/nixos/flake.nix nor /etc/nixos/configuration.nix exists - nothing to install." >&2
  exit 1
fi

# nixos-install's own default config discovery for a classic (non-flake)
# install looks at $mountPoint/etc/nixos/configuration.nix, not
# /etc/nixos/configuration.nix - copying the whole config over first makes
# that resolve correctly with no extra flags, and also leaves the
# installed system with a real /etc/nixos for future nixos-rebuild calls
# (otherwise it'd be empty after reboot, since nothing else puts it there).
mkdir -p /mnt/etc/nixos
cp -a /etc/nixos/. /mnt/etc/nixos/

if [ -f /etc/nixos/flake.nix ]; then
  echo "Running nixos-install for host \"$HOSTNAME\" (needs network access to fetch nixpkgs)..."
  nixos-install --root /mnt --flake "/mnt/etc/nixos#$HOSTNAME"
else
  nixos-install --root /mnt
fi

echo
echo "Install finished. Reboot and remove the ISO to boot into the new system."
