# Wraps each tool's plain shell script (in this directory) as a
# writeShellApplication derivation - keeps the actual bash in real .sh files
# (editable/shellcheck-able on their own) while still getting
# writeShellApplication's PATH-wrapping and shellcheck-at-build-time.
{ pkgs }:
{
  # Small reusable confirmation prompt: echoes the given message, then asks
  # Y/n (default yes) whether to continue. Exit status reflects the answer,
  # so callers use it as `ezdialog "..." && command` or in an `if`.
  ezdialog = pkgs.writeShellApplication {
    name = "ezdialog";
    text = builtins.readFile ./ezdialog.sh;
  };

  # Sets the display to a given WIDTHxHEIGHT via xrandr, auto-detecting the
  # connected output (there's normally exactly one on the machine being
  # installed to) rather than requiring the caller to know its name, which
  # varies (eDP-1, HDMI-1, Virtual-1 in a VM, ...). Backs the resolution
  # buttons in the ezconf terminal panel's Ezmenu.
  ezresolution = pkgs.writeShellApplication {
    name = "ezresolution";
    runtimeInputs = with pkgs; [ xrandr gawk ];
    text = builtins.readFile ./ezresolution.sh;
  };

  # Generates hardware-configuration.nix for whatever's mounted at /mnt, into
  # /etc/nixos (where ezconf edits the config being installed) - pass
  # --no-filesystems to skip fileSystems/swapDevices (e.g. when disko already
  # owns disk layout). Exposed as two ezconf buttons ("with disks" / "without
  # disks") rather than being run automatically by ezpartition/ezinstall, so
  # it's always an explicit choice.
  ezhwconfig = pkgs.writeShellApplication {
    name = "ezhwconfig";
    runtimeInputs = with pkgs; [ util-linux nix ];
    text = builtins.readFile ./ezhwconfig.sh;
  };

  # Guided disk setup: partitions a whole disk (GPT: ESP + optional swap +
  # root), formats it, and mounts the result at /mnt so ezinstall has
  # something to install onto. Asks interactively for the target disk, swap
  # size, and whether to LUKS-encrypt the root partition (mapper name
  # defaults to "rootfs_luks" when encrypted, e.g. to match a
  # `systemd-ask-password --keyname=rootfs_luks` remote-unlock setup). Not
  # the only way to prepare a disk — GParted and a plain shell (disko,
  # manual parted/mkfs) are still available for anything this doesn't cover
  # (multi-disk, existing partitions, btrfs subvolumes...).
  ezpartition = pkgs.writeShellApplication {
    name = "ezpartition";
    runtimeInputs = with pkgs; [ util-linux parted dosfstools e2fsprogs cryptsetup gnugrep ];
    text = builtins.readFile ./ezpartition.sh;
  };

  # The only job of this script: install whatever NixOS system is described
  # by the files currently at /etc/nixos — flake-based or classic
  # configuration.nix — onto whatever's mounted at /mnt.
  # Partitioning/formatting/mounting is out of scope here: do that however
  # fits the config you loaded (ezpartition, disko, GParted, manual
  # parted/mkfs, etc.) before clicking this. Safe to re-run after fixing a
  # config error — it never touches partitioning.
  ezinstall = pkgs.writeShellApplication {
    name = "ezinstall";
    runtimeInputs = with pkgs; [ util-linux nix jq ];
    text = builtins.readFile ./ezinstall.sh;
  };
}
