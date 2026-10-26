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

Two ISOs since 2026-10-25, both in every branch: `eznix-iso` (eznix `main`,
ezsetup's `main` index) and `eznix-iso-develop` (the `eznix-develop` input and
ezsetup's `develop` index; `packages.develop`). `flake.nix` passes `ezBranch`
to the modules (`specialArgs`): `configuration.nix` puts it in the template
source's address, `iso.nix` in the file name. The user wanted develop on all
three repositories to be testable together; branch-specific addresses in the
files were turned down because every merge into `main` would carry them over.
ezinstall's own files are the checkout's. Evaluate both after a change (with
`path:.` while a new file is untracked). The workflow builds either (a choice
when run by hand); only `eznix-iso` from `main` is released: a release per changed
ISO, tagged with the date, never changed afterwards, the three newest kept (since
2026-10-26; before, one release `latest` had its ISO replaced and its tag moved, which
the user saw as GitHub used the wrong way: its dates said nothing about the ISO).
It builds only when eznix's or ezinstall's `main` moved since the newest release (its
notes hold `eznix: SHA` and `ezinstall: SHA`; checked every morning), or by hand: the
templates it installs have flake.locks of their own, so nixpkgs alone is no reason.
An ISO identical to the newest release's is not released (no new version); its commits
are remembered in the Actions cache (`built-EZNIX-EZINSTALL`) so mornings skip them.

## Non-obvious gotchas

- **`nixos-generate-config --dir` bug**: it special-cases `--dir` when it's
  literally the string `"/etc/nixos"` by prefixing `--root` onto it (its own
  default-output-path behavior) — `--dir /etc/nixos` combined with
  `--root /mnt` silently writes to `/mnt/etc/nixos` instead. `ezhwconfig`
  works around this by generating into a throwaway temp dir and copying just
  `hardware-configuration.nix` out to `/etc/nixos`. Hardware-config
  generation is deliberately *not* run automatically by `ezpartition`/
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
  for already-queued events, it doesn't create new ones. `ezpartition` runs
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
  in the buttons inside ezsetup's `nixos/ezvm-system.zip`.
- The panel is a service of its own, started outside the X session:
  `DISPLAY` is exported globally (`environment.variables.DISPLAY = ":0"`,
  since there's only ever one X display on this live ISO) so
  `setxkbmap`/`gparted`/etc. don't need it set per-command, and
  `xhost +local:` is set in `sessionCommands` to let that shell, and root
  through sudo, reach the display at all.
- **Nothing is loaded into `/etc/nixos` at startup** (since 2026-10-22; the
  user wanted eznix's new System sources used instead). The starting setups moved to their own repository on 2026-10-25,
  `../ezsetup` (github.com/kalken/ezsetup); its `nixos/index.json`
  lists the zips next to it and is what `plugins.system.sources` in
  `configuration.nix` points at (raw GitHub address, branch `main`), so a
  template only shows up once it is pushed there and has an entry in the index. An import removes the old suggestions and eznix's
  notice offers to generate them; the `autocomplete` setting that did it by
  itself is gone from eznix (2026-10-25).
  Not built or booted; only evaluated.
- **Autocomplete is eznix's own button, in the page's header**, in install
  mode too since 2026-10-13. Before, eznix left it out there and the ISO had
  one of its own in the install row; the user wanted it back at the top and
  the row's removed ("it does not serve a purpose"). Don't add one again.
- **eznix logs in with system passwords on NixOS** (its `password` option is
  refused by the NixOS module), so the page's login is the `nixos` user's
  own password, set in `configuration.nix`.
- **ezsetup's `nixos/ezvm-system.zip` is built by hand**: unpack, edit, zip again
  (`zip -r -X`). Its `flake.nix` imports the settings with
  `inputs.eznix.lib.jsonDir ./eznix`; eznix installs no loader file in that
  folder. Evaluate it after a change:
  `nix eval path:DIR#nixosConfigurations.default.config.system.build.toplevel.drvPath`.
- **Both the ISO and what it installs build on the stable release**, `26.05`
  at the time: `nixpkgs.url` in `flake.nix` and in the `flake.nix` inside
  ezsetup's `nixos/ezvm-system.zip`, and `stateVersion` in `iso.nix` and in the zip's
  `eznix/system/nix.json`. Until 2026-10-13 all four said `nixos-unstable`
  and `26.11`, while eznix's own templates were on the stable release; the
  user had them made the same ("make them both use stable then"). The number
  is raised by hand when a release comes out, in May and November, here and
  in eznix. Evaluated on a Mac after the change (the ISO's image and the
  installed system's derivation, both 26.05); no ISO was built or booted.
- **The ISO must stay under 2 GiB** (2048 MiB), GitHub's limit for a release
  file; the user asked for that on 2026-10-13. `iso.nix` gets there with zstd
  level 19 and by switching off speechd, pipewire, documentation and ZFS.
  `linux-firmware` (805 MiB, already compressed) stays, since the installer
  has to work on real hardware. The ISO is about 54 MiB larger than its
  squashfs. Measured but not applied: `fonts.enableDefaultPackages = false`
  saves another 64 MiB (CJK fonts), xz another 60; turning off
  `system.tools.nixos-rebuild` saves nothing (python stays). Check the size
  of `result/iso/*.iso` after anything that adds packages.
- `system.stateVersion` in `iso.nix` is the live ISO's own state version, not
  the target system's — don't confuse it with whatever `stateVersion` the
  installed config specifies.

## Working in this repo

- `iso.nix` holds only what's specific to being a live-CD image (squashfs
  compression, not cloning a config into `/etc/nixos` on boot, the live ISO's
  own `stateVersion`) and imports `configuration.nix`.
- The starting configs the System menu offers are in ezsetup (`nixos/*.zip`,
  listed by `nixos/index.json`), not here since 2026-10-25.
- `configuration.nix` is the live environment: session/desktop setup,
  packages, and eznix's configuration and buttons.
- `pkgs/` holds the `ezdialog`/`ezresolution`/`ezhwconfig`/`ezpartition`/
  `ezinstall`/`ezvalidate` tools — each a plain `.sh` script, wrapped as a
  `writeShellApplication` derivation in `pkgs/packages.nix`. Changes to the
  installed system's *behavior toward the target machine* (partitioning
  assumptions, install logic) belong in `pkgs/ezpartition.sh`/
  `pkgs/ezinstall.sh`. `ezvalidate` (2026-10-25) evaluates each
  `nixosConfigurations` entry of `/etc/nixos` (or `--flake DIR`, or the hosts
  named) down to `toplevel.drvPath`, building nothing; ezsetup's ezvm template
  runs `sudo ezvalidate` first in "Install this setup (Guided)", and the
  Ezmenu has "Check setup" for it alone (save first). As root, like
  ezinstall, since evaluating writes `flake.lock` into the flake. Tried on a Mac
  against the ezvm template: valid, a missing hardware file, a wrong option
  name, an unknown host; not built into an ISO or run on one.
- Changes to *which* eznix version or nixpkgs version is used belong in
  `flake.nix`.
- There's no CI or test suite here; the only verification available is
  `nix build` (or `nix eval` for a quicker check) succeeding, and, if
  actually validating behavior, booting the resulting ISO.
- Never commit without being asked: a change stays in the working tree
  until the user says to commit it, and the report says it is uncommitted.
  (The user's rule since 2026-10-13; before, this file said to commit
  locally without asking.) Never push without being asked either.
- Always commit to `develop` first. Only merge `develop` into `main`; never
  commit to `main`.
- Don't add `Co-Authored-By: Claude ...` (or any other Claude/Anthropic
  attribution) to commit messages or PR descriptions in this repo.
- Format the Nix files the standard way, with `nixfmt` (RFC 166), and check
  with `nix run nixpkgs#nixfmt -- --check $(git ls-files '*.nix')` after
  editing any of them. Any Python file would follow PEP 8 (there are none
  now); the shell scripts in `pkgs/` are not run through a formatter.
- Don't update this file for every small change — keep it to non-obvious
  gotchas and conventions. User-facing behavior (buttons, usage, options)
  belongs in README.md instead.
