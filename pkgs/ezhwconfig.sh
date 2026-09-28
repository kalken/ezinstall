#!/usr/bin/env bash
# Only --no-filesystems' fileSystems/swapDevices detection actually needs
# something mounted at /mnt to read UUIDs/mountpoints from - kernel-module
# detection reflects the currently-running live machine either way, so
# skip the check entirely when disk layout isn't being generated.
NEEDS_MOUNT=1
for arg in "$@"; do
  [ "$arg" = "--no-filesystems" ] && NEEDS_MOUNT=0
done
if [ "$NEEDS_MOUNT" = 1 ] && ! mountpoint -q /mnt; then
  echo "Nothing mounted at /mnt - partition and mount your target disk there first, or use --no-filesystems if you don't need disk layout detected." >&2
  exit 1
fi

# Generated into a throwaway dir, then only hardware-configuration.nix is
# copied to /etc/nixos: nixos-generate-config special-cases --dir when
# it's literally the string "/etc/nixos" by prefixing --root onto it
# (its own default-output-path behavior), which would silently put the
# file at /mnt/etc/nixos instead otherwise.
HWCONFIG_TMP=$(mktemp -d)
nixos-generate-config --root /mnt --dir "$HWCONFIG_TMP" "$@"
mkdir -p /etc/nixos
cp "$HWCONFIG_TMP/hardware-configuration.nix" /etc/nixos/hardware-configuration.nix
rm -rf "$HWCONFIG_TMP"
echo "Wrote /etc/nixos/hardware-configuration.nix."
