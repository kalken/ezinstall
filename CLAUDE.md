# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

For what this repo is, how to build/boot it, and what the ISO actually does, see [README.md](README.md) — keep that up to date instead of duplicating it here. This file is for things an agent editing this code needs to know that aren't obvious from reading `iso.nix`/`flake.nix` themselves.

## Commands

Before building the ISO, always check whether `kalken/ezconf`'s branch
tracked in `flake.nix` (check there for the current ref — it has moved
between `develop` and `testing` before) has moved past the commit currently
pinned in `flake.lock`, and if so run `nix flake update ezconf` first. The
user (vibecodingftw@gmail.com) maintains ezconf itself, so whichever branch
is tracked is a moving target they push fixes to directly — building
against a stale pin has already caused a real bug
(the `trustedHosts = [ "*" ]` wildcard silently not working) to ship in the
ISO after it had already been fixed upstream.

Build the ISO:
```
nix build
```
This produces a multi-GB ISO and takes a while — **ask before running it**,
rather than building automatically after every edit. `nix eval` (below) is
the fast, ask-free way to sanity-check a change.

Evaluate without building, for a fast syntax/eval check:
```
nix eval .#nixosConfigurations.ezconf-iso.config.system.build.isoImage.outPath
```

## Non-obvious gotchas

- **`nixos-generate-config --dir` bug**: it special-cases `--dir` when it's
  literally the string `"/etc/nixos"` by prefixing `--root` onto it (its own
  default-output-path behavior) — `--dir /etc/nixos` combined with
  `--root /mnt` silently writes to `/mnt/etc/nixos` instead. `ezhwconfig`
  works around this by generating into a throwaway temp dir and copying just
  `hardware-configuration.nix` out to `/etc/nixos`. Hardware-config
  generation is deliberately *not* run automatically by `ezparted`/
  `ezinstall` — it's `ezhwconfig`'s own job, exposed as explicit buttons, so
  it's always a choice rather than something baked into another script's
  logic.
- **Never pass `--force` to `nixos-generate-config` here**: it always
  overwrites `hardware-configuration.nix` regardless of that flag, but
  `--force` also strips the "don't overwrite" guard on `configuration.nix` —
  passing it would risk clobbering a real classic (non-flake) config with a
  generic stub.
- **Classic (non-flake) `nixos-install --root /mnt` looks for config at
  `$mountPoint/etc/nixos/configuration.nix`**, not `/etc/nixos/configuration.nix`
  — even though ezconf edits the latter. `ezinstall` copies all of `/etc/nixos`
  to `/mnt/etc/nixos` before installing to make that resolve with no extra
  flags (and as a side effect, leaves the installed system with a real
  `/etc/nixos` for future `nixos-rebuild` calls).
- **`lsblk`'s FSTYPE/LABEL/UUID columns read udev's cached device database**
  (`/run/udev/data/...`), not a live probe — `mkfs`/`mkswap` writing to a block
  device doesn't itself generate a udev event, so a partition can show blank
  in `lsblk` indefinitely after formatting even though `blkid <dev>` (a real
  live probe) sees it fine. `udevadm settle` doesn't fix this — it only waits
  for already-queued events, it doesn't create new ones. `ezparted` runs
  `udevadm trigger --settle` on each formatted partition to force udev to
  re-probe.
- **Commands run through ezconf's terminal panel run as `root`**, not as the
  `nixos` user the graphical X session belongs to — `setxkbmap` and `gparted`
  need `DISPLAY=:0` set explicitly on their button commands, and
  `xhost +local:` is set in `sessionCommands` to let root's shell reach that
  display at all.
- `system.stateVersion` in `iso.nix` is the live ISO's own state version, not
  the target system's — don't confuse it with whatever `stateVersion` the
  installed config specifies.

## Working in this repo

- `iso.nix` holds only what's specific to being a live-CD image (squashfs
  compression, not cloning a config into `/etc/nixos` on boot, restoring
  `templates/default.zip` into `/etc/nixos` before ezconf's service starts, the
  live ISO's own `stateVersion`) and imports `configuration.nix`.
- `templates/default.zip` is what actually seeds a fresh boot's `/etc/nixos` —
  swap it for a different backup to change the starting config.
  `example/flake.nix` is unused by the ISO itself; it's only a hand-written
  reference kept around for starting from scratch.
- `configuration.nix` is the live environment: session/desktop setup,
  packages, and ezconf's configuration and buttons.
- `pkgs/` holds the `ezdialog`/`ezresolution`/`ezhwconfig`/`ezpartition`/
  `ezinstall` tools — each a plain `.sh` script, wrapped as a
  `writeShellApplication` derivation in `pkgs/packages.nix`. Changes to the
  installed system's *behavior toward the target machine* (partitioning
  assumptions, install logic) belong in `pkgs/ezpartition.sh`/
  `pkgs/ezinstall.sh`.
- Changes to *which* ezconf version or nixpkgs version is used belong in
  `flake.nix`/`flake.lock`.
- There's no CI or test suite here; the only verification available is
  `nix build` (or `nix eval` for a quicker check) succeeding, and, if
  actually validating behavior, booting the resulting ISO.
- Commit changes locally (no need to ask) once they're done — don't leave
  them sitting uncommitted. Still don't push without being asked.
- Don't add `Co-Authored-By: Claude ...` (or any other Claude/Anthropic
  attribution) to commit messages or PR descriptions in this repo.
- Don't update this file for every small change — keep it to non-obvious
  gotchas and conventions. User-facing behavior (buttons, usage, options)
  belongs in README.md instead.
