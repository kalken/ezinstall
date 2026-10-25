# ezinstall

A bootable NixOS live ISO whose sole purpose is running [eznix](https://github.com/kalken/eznix) as a graphical installer. Boot it, a browser opens straight into the eznix UI, and from there you load a target system's config and either install it fresh or reconfigure a running machine.

## ✨ Features

- Boots straight into a browser pointed at eznix — no login prompt beyond eznix's own
- Guided disk partitioner (`ezpartition`): GPT (ESP + optional swap + root), optional LUKS encryption, configurable boot/swap sizes
- One-click installer (`ezinstall`): flake or classic `configuration.nix`
- On-demand `hardware-configuration.nix` generation (`ezhwconfig`), with or without disk layout
- Reachable from other machines on the network, not just the ISO's own screen
- Keyboard layout switcher, GParted, and eznix's own terminal panel for anything the guided tools don't cover

## 🚀 Quick Start

```sh
nix build --no-write-lock-file 'github:kalken/ezinstall'
```

The ISO lands at `./result/iso/*.iso`. It's just under 2 GB (kept there so it fits as a GitHub release file) and takes a while to build.

Boot the ISO (physical machine, or a VM — tested with QEMU/virt-manager, UEFI or BIOS). It auto-logs in, launches Firefox (kiosk mode) at `http://localhost:9090`, and that's eznix.

## 🔐 Login

| | |
|---|---|
| Username | `nixos` |
| Password | `eznix` |

Fixed credentials over plain HTTP — fine for an ephemeral live session, not something to expose beyond a trusted network.

## 🌐 Network Access

eznix listens on every network interface, so any machine on the same network can open `http://<iso-ip>:9090` — not just the ISO's own screen. This is deliberate: it means anyone on that network can reach and use it while the ISO is booted. Other host names are refused, so a website can't point its own name at the ISO to reach it.

## 🖥️ Using the ISO

The ISO's own tools are in the **Ezmenu** button of the eznix terminal panel's install row (this is a dedicated install image, so `mode = "install"` is set throughout):

| Ezmenu ▸ | What it does |
|---|---|
| **Keyboard layout** ▸ US / UK / German / Swedish / French | Switches the live session's keyboard layout (`setxkbmap`) |
| **List disks** | `lsblk` — see what's attached before partitioning |
| **Launch terminal** | Opens an `xterm` on the ISO's own screen |
| **Launch Firefox** | Opens another Firefox window |
| **Partition** ▸ GParted | Graphical partitioner, for anything the guided tool doesn't cover |
| **Partition** ▸ Partition disks (guided) | Runs `ezpartition` (below) |
| **Resolution** ▸ 1024x768 … 3840x2160 | Sets the screen resolution of the live session (`ezresolution`) |
| **Hardware config** ▸ With disks | Runs `ezhwconfig` — full `hardware-configuration.nix`, including disk layout. Needs `/mnt` already mounted, i.e. run this after partitioning |
| **Hardware config** ▸ Without disks | Runs `ezhwconfig --no-filesystems` — for when `disko` or a hand-written config already owns disk layout. Doesn't need `/mnt` mounted — safe to run before partitioning |
| **Install NixOS** | Runs `ezinstall` (below) |
| **Reboot** | Reboots the machine |

A starting setup imported from the System menu (see Customizing) can add buttons of its own beside it, such as a one-click guided install; its own documentation describes them.

eznix's own terminal panel is a real interactive shell underneath all of this, running as the `nixos` user (`sudo` needs no password there) — use it to `git clone` a flake, hand-write a `configuration.nix`, run `disko`, or do anything else these buttons don't cover, before clicking Install NixOS.

## 💽 Guided Partitioning — `ezpartition`

Interactive, whole-disk only (not for multi-disk or existing-partition layouts):

1. Pick a target disk (e.g. `sda`, `nvme0n1`) and confirm — **this erases the whole disk**.
2. Optionally LUKS-encrypt root (opened as `/dev/mapper/rootfs_luks`).
3. Boot (ESP) size — default `512M`.
4. Swap size, or `0` to skip — default `4G`.

It then partitions (GPT: ESP + optional swap + root), formats everything, and mounts the result at `/mnt`/`/mnt/boot`. If you chose LUKS, it prints the `boot.initrd.luks.devices` line (with UUID) your target config needs.

From there, load your actual config — clone a flake, or write `configuration.nix` by hand — generate `hardware-configuration.nix` (below), and click **Install NixOS**.

## 🔧 Hardware Config — `ezhwconfig`

Generates `hardware-configuration.nix` for whatever's mounted at `/mnt`, written to `/etc/nixos` (where eznix edits the config being installed). Two variants, since only you know whether something else — `disko`, a hand-written config — already owns disk layout:

- **With disks** — full generation, including `fileSystems`/`swapDevices`. Use this for a `parted`/`mkfs`-formatted disk (e.g. via GParted) where nothing else defines them.
- **Without disks** — skips `fileSystems`/`swapDevices`, leaving them to `disko` or your own config.

Not run automatically by `ezpartition` or `ezinstall` — always an explicit choice, run whenever you need it (including to refresh after re-partitioning).

## 📥 Installing — `ezinstall`

Assumes partitioning/mounting is already done at `/mnt` (by `ezpartition`, GParted, `disko`, or manual `parted`/`mkfs` — it doesn't care which), and that `hardware-configuration.nix` is already in place if your config needs one. It:

1. Detects whether `/etc/nixos` has a flake (`nixosConfigurations`, prompting if there's more than one host) or a classic `configuration.nix`.
2. Copies the whole config to `/mnt/etc/nixos`, then runs `nixos-install`.
3. Copies eznix's suggestions to the installed system, if they were generated here (**Autocomplete**), so it starts with them. If they weren't, eznix there offers to generate them.

Re-run-safe — it never touches partitioning, so fixing a config error and clicking Install NixOS again just works.

## ⚙️ Customizing

The repo is laid out as:

- **`flake.nix`** — wires nixpkgs, the `eznix` input, and `iso.nix` into the `eznix-iso` NixOS system that gets built.
- **`iso.nix`** — only what's specific to being a live-CD image (compression, not cloning a config on boot, the live ISO's own `stateVersion`). Imports `configuration.nix`.
- **`configuration.nix`** — the live session, eznix's configuration and buttons.
- **`pkgs/`** — the `ezdialog`/`ezresolution`/`ezhwconfig`/`ezpartition`/`ezinstall` tools: each is a plain `.sh` script here, wrapped as a `writeShellApplication` derivation by `pkgs/packages.nix`.
- **Starting setups** live in [ezsetup](https://github.com/kalken/ezsetup) (`nixos/`, e.g. `ezvm-system.zip`: a full `/etc/nixos` backup with flake, `eznix/` tabs, plugins). Nothing is loaded at boot: they are listed under **System ▸ Start from a template** (the `system` plugin's `sources` in `configuration.nix` points at ezsetup's `nixos/index.json` on GitHub, branch `main`), and choosing one imports it.

## 📝 Notes

- `installer.cloneConfig = false` — the live ISO's own config is never copied into `/etc/nixos` on boot. `/etc/nixos` starts empty: pick a starting setup from **System ▸ Start from a template** (needs the network), `git clone` your own flake or hand-write `configuration.nix`.
- An import from the System menu removes the old suggestions; a notice in the corner then offers to generate them for the new system (the **Autocomplete** button at the top does the same, and runs `eznix-autocomplete` in the terminal). Nothing is generated at boot.
- Nothing in eznix runs as root: its terminal panel (and anything run through its buttons) runs as the `nixos` user, and the buttons that need root (partitioning, hardware config, install, GParted, reboot) say `sudo`, which that user has without a password on the live image. The panel is a service of its own, started outside the graphical session, so `DISPLAY` is exported globally (`environment.variables.DISPLAY = ":0"`) and `xhost +local:` is set at session startup, so `setxkbmap`, GParted, etc. can still reach that display.
- To keep the image under 2 GB, the live session has no sound, no speech synthesis, no manuals or `man` pages, and no ZFS support (so no installing onto ZFS from it). Firmware for Wi-Fi and graphics is all there.
- From a checkout it is `nix build` in the folder, and `nix eval .#nixosConfigurations.eznix-iso.config.system.build.isoImage.outPath` checks that it evaluates without building anything.
- `flake.lock` isn't committed (it's in `.gitignore`), so every build takes `kalken/eznix`'s default branch as it is then — no `nix flake update` needed to pick up fixes. It is also why the command above says `--no-write-lock-file`: built straight from GitHub, Nix has nowhere to write one and stops without it.
- GitHub can build the ISO: Actions, **Build ISO**, Run workflow. It is kept there as a download (the run's artifact) for 30 days, and the run fails if the ISO is over 2 GiB. No release is made.
- There's no test suite — the only verification available is `nix build` (or `nix eval` for a quicker check) succeeding, and, if actually validating behavior, booting the resulting ISO.
