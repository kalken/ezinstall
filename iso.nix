{ pkgs, lib, ... }:

let
  # builtins.pathExists never errors on a missing path (unlike interpolating
  # a nonexistent path literal into a string, which does) - so this is safe
  # to check even when the zip has been deleted.
  backupZip = ./templates/default.zip;
  hasBackup = builtins.pathExists backupZip;
in
{
  imports = [ ./configuration.nix ];

  image.baseName = lib.mkForce "ezconf-live";

  # Zstd is faster to build and still compresses well.
  isoImage.squashfsCompression = "zstd -Xcompression-level 6";

  # Don't clone the live ISO's own config into /etc/nixos on boot — leave it
  # empty so whatever gets loaded through ezconf (a real flake, a classic
  # configuration.nix, a git checkout, ...) has a clean directory to land in.
  installer.cloneConfig = false;

  # Restore templates/default.zip into /etc/nixos as a starting point, before
  # ezconf's own service starts (activation scripts run during early boot,
  # ahead of regular systemd services). `-o` forces overwrite rather than
  # prompting, since nothing on this live image persists across reboots
  # anyway - re-running this on every boot always lands the same backup.
  # Only wired up when the zip actually exists - without one, the ISO just
  # boots into an empty /etc/nixos, same as before templates/default.zip
  # existed at all.
  system.activationScripts.ezconfRestoreBackup = lib.mkIf hasBackup ''
    mkdir -p /etc/nixos
    ${pkgs.unzip}/bin/unzip -o -q ${backupZip} -d /etc/nixos
  '';

  # This is the live ISO's own state version, not the target system's - don't
  # confuse it with whatever stateVersion the installed config specifies.
  system.stateVersion = "26.11";
}
