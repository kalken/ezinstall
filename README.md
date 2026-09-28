# ezinstall

A bootable NixOS live ISO whose sole purpose is running [ezconf](https://github.com/kalken/ezconf) as a graphical installer. Boot it, a browser opens straight into the ezconf UI, and from there you load a target system's config and either install it fresh or reconfigure a running machine.

## ✨ Features

- Boots straight into a browser pointed at ezconf — no login prompt beyond ezconf's own
- Guided disk partitioner (`ezparted`): GPT (ESP + optional swap + root), optional LUKS encryption, configurable boot/swap sizes
- One-click installer (`ezinstall`): flake or classic `configuration.nix`
- On-demand `hardware-configuration.nix` generation (`ezhwconfig`), with or without disk layout
- Reachable from other machines on the network, not just the ISO's own screen
- Keyboard layout switcher, GParted, and ezconf's own terminal panel for anything the guided tools don't cover

## 🚀 Quick Start

This repo tracks `kalken/ezconf`'s `master` branch, but `flake.lock` pins an exact commit — check whether it's fallen behind before building:

```sh
git ls-remote https://github.com/kalken/ezconf master
grep -A2 '"rev": "' flake.lock | head -1   # what's currently pinned
```

If they differ, pull in the latest commit first:

```sh
nix flake update ezconf
```

Build the ISO:

```sh
nix build
```

The result lands at `./result/iso/*.iso`. It's a multi-GB image and takes a while to build.

Fast syntax/eval check without a full build:

```sh
nix eval .#nixosConfigurations.ezconf-iso.config.system.build.isoImage.outPath
```

Boot the ISO (physical machine, or a VM — tested with QEMU/virt-manager, UEFI or BIOS). It auto-logs in, launches Firefox (kiosk mode) at `http://localhost:9090`, and that's ezconf.

## 🔐 Login

| | |
|---|---|
| Username | `nixos` |
| Password | `ezconf` |

Fixed credentials over plain HTTP — fine for an ephemeral live session, not something to expose beyond a trusted network.

## 🌐 Network Access

ezconf listens on `0.0.0.0`, so any machine on the same network can open `http://<iso-ip>:9090` — not just the ISO's own screen. This is deliberate: it means anyone on that network can reach and use it while the ISO is booted.

## 🖥️ Using the ISO

The ezconf terminal panel's button bar (all buttons show together — this is a dedicated install image, so `mode = "install"` is set throughout):

| Button | What it does |
|---|---|
| **Keyboard layout** ▸ US / UK / German / Swedish / French | Switches the live session's keyboard layout (`setxkbmap`) |
| **List disks** | `lsblk` — see what's attached before partitioning |
| **Partition** ▸ Open GParted | Graphical partitioner, for anything the guided tool doesn't cover |
| **Partition** ▸ Partition disks (guided) | Runs `ezparted` (below) |
| **Hardware config** ▸ With disks | Runs `ezhwconfig` — full `hardware-configuration.nix`, including disk layout. Needs `/mnt` already mounted, i.e. run this after partitioning |
| **Hardware config** ▸ Without disks | Runs `ezhwconfig --no-filesystems` — for when `disko` or a hand-written config already owns disk layout. Doesn't need `/mnt` mounted — safe to run before partitioning |
| **Install NixOS** | Runs `ezinstall` (below) |
| **Reboot** | Reboots the machine |

ezconf's own terminal panel is a real interactive shell underneath all of this — use it to `git clone` a flake, hand-write a `configuration.nix`, run `disko`, or do anything else these buttons don't cover, before clicking Install NixOS.

## 💽 Guided Partitioning — `ezparted`

Interactive, whole-disk only (not for multi-disk or existing-partition layouts):

1. Pick a target disk (e.g. `sda`, `nvme0n1`) and confirm — **this erases the whole disk**.
2. Optionally LUKS-encrypt root (opened as `/dev/mapper/luks-rootfs`).
3. Boot (ESP) size — default `512M`.
4. Swap size, or `0` to skip — default `4G`.

It then partitions (GPT: ESP + optional swap + root), formats everything, and mounts the result at `/mnt`/`/mnt/boot`. If you chose LUKS, it prints the `boot.initrd.luks.devices` line (with UUID) your target config needs.

From there, load your actual config — clone a flake, or write `configuration.nix` by hand — generate `hardware-configuration.nix` (below), and click **Install NixOS**.

## 🔧 Hardware Config — `ezhwconfig`

Generates `hardware-configuration.nix` for whatever's mounted at `/mnt`, written to `/etc/nixos` (where ezconf edits the config being installed). Two variants, since only you know whether something else — `disko`, a hand-written config — already owns disk layout:

- **With disks** — full generation, including `fileSystems`/`swapDevices`. Use this for a `parted`/`mkfs`-formatted disk (e.g. via GParted) where nothing else defines them.
- **Without disks** — skips `fileSystems`/`swapDevices`, leaving them to `disko` or your own config.

Not run automatically by `ezparted` or `ezinstall` — always an explicit choice, run whenever you need it (including to refresh after re-partitioning).

## 📥 Installing — `ezinstall`

Assumes partitioning/mounting is already done at `/mnt` (by `ezparted`, GParted, `disko`, or manual `parted`/`mkfs` — it doesn't care which), and that `hardware-configuration.nix` is already in place if your config needs one. It:

1. Detects whether `/etc/nixos` has a flake (`nixosConfigurations`, prompting if there's more than one host) or a classic `configuration.nix`.
2. Copies the whole config to `/mnt/etc/nixos`, then runs `nixos-install`.

Re-run-safe — it never touches partitioning, so fixing a config error and clicking Install NixOS again just works.

## ⚙️ Customizing

The repo is laid out as:

- **`flake.nix`** — wires nixpkgs, the pinned `ezconf` input, and `iso.nix` into the `ezconf-iso` NixOS system that gets built.
- **`iso.nix`** — only what's specific to being a live-CD image (compression, not cloning a config on boot, the live ISO's own `stateVersion`). Imports `configuration.nix`.
- **`configuration.nix`** — the live session, ezconf's configuration and buttons.
- **`pkgs/`** — the `ezdialog`/`ezresolution`/`ezhwconfig`/`ezpartition`/`ezinstall` tools: each is a plain `.sh` script here, wrapped as a `writeShellApplication` derivation by `pkgs/packages.nix`.
- **`templates/default.zip`** — a full `/etc/nixos` backup (flake, `ezconf/` tabs, plugins). If present, it's auto-loaded: unpacked into `/etc/nixos` automatically on every boot, before ezconf's own service starts. This is what seeds the ISO's starting config — replace this zip to change what a fresh boot starts with.

## 📝 Notes

- `installer.cloneConfig = false` — the live ISO's own config is never copied into `/etc/nixos` on boot. Instead, `templates/default.zip` is unpacked there as a starting point (see Customizing) — `git clone` your own flake or hand-write `configuration.nix` over it if you'd rather start from scratch.
- `generateAutocomplete = false` — ezconf doesn't run `ezconf-mkoptions` automatically on first start (which would eval the whole target flake on every fresh boot). Use the UI's own `↻ Autocomplete` button once you've loaded a config that actually evaluates.
- `ezconf`'s terminal panel (and anything run through its buttons) runs as `root`, not as the `nixos` user the graphical session belongs to — `DISPLAY` is exported globally (`environment.variables.DISPLAY = ":0"`) and `xhost +local:` is set at session startup, so `setxkbmap`, GParted, etc. can still reach that display.
- There's no CI or test suite — the only verification available is `nix build` (or `nix eval` for a quicker check) succeeding, and, if actually validating behavior, booting the resulting ISO.
