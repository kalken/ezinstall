{ pkgs, lib, ezBranch, ... }:

{
  imports = [ ./configuration.nix ];

  # eznix-live, -develop for the test ISO, -aarch64 for ARM; x86_64 has no suffix.
  image.baseName = lib.mkForce (
    lib.concatStrings [
      "eznix-live"
      (lib.optionalString (ezBranch != "main") "-${ezBranch}")
      (lib.optionalString pkgs.stdenv.hostPlatform.isAarch64 "-aarch64")
    ]
  );

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
  # empty so whatever gets loaded through eznix (a system from its System
  # menu, a real flake, a classic configuration.nix, a git checkout, ...) has
  # a clean directory to land in. Nothing is loaded at startup; the starting
  # setups are offered as a source in configuration.nix.
  installer.cloneConfig = false;

  # This is the live ISO's own state version, not the target system's - don't
  # confuse it with whatever stateVersion the installed config specifies.
  system.stateVersion = "26.05";
}
