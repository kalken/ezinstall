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

  image.baseName = lib.mkForce "eznix-live";

  # The ISO has to stay under 2 GiB, GitHub's limit for a release file. Level
  # 19 is about 110 MiB smaller than level 6 here and still decompresses
  # fast; "xz -Xdict-size 100%" is another 60 MiB smaller but slower to boot.
  isoImage.squashfsCompression = "zstd -Xcompression-level 19";

  # For the same limit, what the graphical session and the installer profile
  # switch on by default and nothing here uses: speech synthesis (its voices
  # alone are 260 MiB in the image), the sound server, the manuals and man
  # pages, and ZFS (which also ends the forceImportRoot warning on every
  # evaluation). Firmware stays: it is a third of the image, and what makes
  # Wi-Fi and graphics work on the machine being installed.
  services.speechd.enable = lib.mkForce false;
  services.pipewire.enable = lib.mkForce false;
  documentation.enable = lib.mkForce false;
  documentation.nixos.enable = lib.mkForce false;
  boot.supportedFilesystems.zfs = lib.mkForce false;

  # Don't clone the live ISO's own config into /etc/nixos on boot — leave it
  # empty so whatever gets loaded through eznix (a real flake, a classic
  # configuration.nix, a git checkout, ...) has a clean directory to land in.
  installer.cloneConfig = false;

  # Restore templates/default.zip into /etc/nixos as a starting point, before
  # eznix's own service starts (activation scripts run during early boot,
  # ahead of regular systemd services), and before eznix's own activation
  # script (the `deps` below): that one hands /etc/nixos and everything in it
  # to the `eznix` group, which is what lets the editor - an unprivileged
  # service - and the `nixos` user write what root unpacked here. `-o` forces overwrite rather than
  # prompting, since nothing on this live image persists across reboots
  # anyway - re-running this on every boot always lands the same backup.
  # Only wired up when the zip actually exists - without one, the ISO just
  # boots into an empty /etc/nixos, same as before templates/default.zip
  # existed at all.
  system.activationScripts.ezinstallRestoreBackup = lib.mkIf hasBackup ''
    mkdir -p /etc/nixos
    ${pkgs.unzip}/bin/unzip -o -q ${backupZip} -d /etc/nixos
  '';
  system.activationScripts.eznix.deps = lib.mkIf hasBackup [ "ezinstallRestoreBackup" ];

  # This is the live ISO's own state version, not the target system's - don't
  # confuse it with whatever stateVersion the installed config specifies.
  system.stateVersion = "26.05";
}
