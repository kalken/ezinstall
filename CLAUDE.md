# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

For what this repo is, how to build/boot it, and what the ISO actually does, see [README.md](README.md) — keep that up to date instead of duplicating it here. This file is for things an agent editing this code needs to know that aren't obvious from reading `iso.nix`/`flake.nix` themselves.

## Commands

`flake.lock` is deliberately not committed (it's in `.gitignore`). The user
(vibecodingftw@gmail.com) maintains `kalken/eznix` itself and pushes fixes
to the tracked branch directly, and a stale pin once shipped an
already-fixed bug (ezconf's `trustedHosts = [ "*" ]` wildcard silently not
working, when the ISO was still built on ezconf) in the ISO. Since Nix only sees git-tracked files in a flake, an
ignored lock file is never read back, so every evaluation re-resolves the
inputs to their latest commits. Don't re-add `flake.lock` to git.

Build the ISO:
```
nix build
```
This produces a multi-GB ISO and takes a while — **ask before running it**,
rather than building automatically after every edit. `nix eval` (below) is
the fast, ask-free way to sanity-check a change.

Evaluate without building, for a fast syntax/eval check:
```
nix eval .#nixosConfigurations.eznix-iso.config.system.build.isoImage.outPath
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
  — even though eznix edits the latter. `ezinstall` copies all of `/etc/nixos`
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
- **Commands run through eznix's terminal panel run as the `nixos` user**,
  never as root (nothing in eznix does; until 2026-10-12 the ISO was built on
  ezconf, whose panel was root's). So every button whose command needs root
  says `sudo` (`sudo ezpartition`, `sudo ezhwconfig`, `sudo ezinstall`,
  `sudo -E gparted`, `sudo reboot`), which works without a password because
  the installer image sets `security.sudo.wheelNeedsPassword = false`. The
  scripts in `pkgs/` still assume they are root and are not changed for it. A
  new button that needs root must say `sudo` too, in `configuration.nix` and
  in the buttons inside `templates/default.zip`.
- The panel is a service of its own, started outside the X session:
  `DISPLAY` is exported globally (`environment.variables.DISPLAY = ":0"`,
  since there's only ever one X display on this live ISO) so
  `setxkbmap`/`gparted`/etc. don't need it set per-command, and
  `xhost +local:` is set in `sessionCommands` to let that shell, and root
  through sudo, reach the display at all.
- **`/etc/nixos` is unpacked by root and written by an unprivileged
  service.** eznix's own activation script gives the flake to the `eznix`
  group (`flakeWritable`, on by default); `iso.nix` makes that script depend
  on the one that unpacks `templates/default.zip`, so the order is fixed.
  Don't unpack anywhere later than activation.
- **eznix shows no Autocomplete button in its header in install mode**, so
  the ISO has one of its own in the install row, running the same
  `eznix-autocomplete`.
- **eznix logs in with system passwords on NixOS** (its `password` option is
  refused by the NixOS module), so the page's login is the `nixos` user's
  own password, set in `configuration.nix`.
- **`templates/default.zip` is built by hand**: unpack, edit, zip again
  (`zip -r -X`). Its `flake.nix` imports the settings with
  `inputs.eznix.lib.jsonDir ./eznix`; eznix installs no loader file in that
  folder. Evaluate it after a change:
  `nix eval path:DIR#nixosConfigurations.default.config.system.build.toplevel.drvPath`.
- **Both the ISO and what it installs build on the stable release**, `26.05`
  at the time: `nixpkgs.url` in `flake.nix` and in the `flake.nix` inside
  `templates/default.zip`, and `stateVersion` in `iso.nix` and in the zip's
  `eznix/system/nix.json`. Until 2026-10-13 all four said `nixos-unstable`
  and `26.11`, while eznix's own templates were on the stable release; the
  user had them made the same ("make them both use stable then"). The number
  is raised by hand when a release comes out, in May and November, here and
  in eznix. Evaluated on a Mac after the change (the ISO's image and the
  installed system's derivation, both 26.05); no ISO was built or booted.
- `system.stateVersion` in `iso.nix` is the live ISO's own state version, not
  the target system's — don't confuse it with whatever `stateVersion` the
  installed config specifies.

## Working in this repo

- `iso.nix` holds only what's specific to being a live-CD image (squashfs
  compression, not cloning a config into `/etc/nixos` on boot, restoring
  `templates/default.zip` into `/etc/nixos` before eznix's service starts, the
  live ISO's own `stateVersion`) and imports `configuration.nix`.
- `templates/default.zip` is what actually seeds a fresh boot's `/etc/nixos` —
  swap it for a different backup to change the starting config.
- `configuration.nix` is the live environment: session/desktop setup,
  packages, and eznix's configuration and buttons.
- `pkgs/` holds the `ezdialog`/`ezresolution`/`ezhwconfig`/`ezpartition`/
  `ezinstall` tools — each a plain `.sh` script, wrapped as a
  `writeShellApplication` derivation in `pkgs/packages.nix`. Changes to the
  installed system's *behavior toward the target machine* (partitioning
  assumptions, install logic) belong in `pkgs/ezpartition.sh`/
  `pkgs/ezinstall.sh`.
- Changes to *which* eznix version or nixpkgs version is used belong in
  `flake.nix`.
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
