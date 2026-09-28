#!/usr/bin/env bash
# Every prompt below can be preset via a flag, to skip it (e.g. for
# scripting or just to avoid retyping the same answer every run). The
# "type the disk name again" safety prompt is the exception - it's only
# skipped by --yes, not merely by passing --disk, since it's a
# confirmation of intent rather than a value to supply.
usage() {
  cat <<'USAGE'
Usage: ezpartition [--disk NAME] [--boot-size SIZE] [--swap-size SIZE|--no-swap]
                   [--boot-label NAME] [--swap-label NAME] [--root-label NAME]
                   [--encrypt|--no-encrypt] [--yes]

  --disk NAME        e.g. sda, nvme0n1 (skips the disk-selection prompt)
  --boot-size SIZE   e.g. 512M or 1G (skips the boot-size prompt)
  --swap-size SIZE   e.g. 4G or 512M (skips the swap prompt)
  --no-swap          same as --swap-size 0 (skips the swap prompt)
  --boot-label NAME  partition/filesystem label for the ESP (default: bootfs;
                      FAT label is truncated to 11 chars)
  --swap-label NAME  partition/filesystem label for swap (default: swapfs)
  --root-label NAME  partition/filesystem label for root (default: rootfs;
                      ext4 label is truncated to 16 chars)
  --luks-label NAME  LUKS mapper name for root when encrypted
                      (default: rootfs_luks)
  --encrypt          LUKS-encrypt root (skips the encrypt prompt)
  --no-encrypt       leave root unencrypted (skips the encrypt prompt);
                      this is also the default if the prompt is left blank
  --yes, -y          also skip the "type the disk name again" confirmation
USAGE
}

DISKNAME="" BOOTSIZE="" SWAPSIZE="" ENCRYPT="" ASSUME_YES=0
BOOT_LABEL="bootfs" SWAP_LABEL="swapfs" ROOT_LABEL="rootfs" LUKS_LABEL="rootfs_luks"
while [ $# -gt 0 ]; do
  case "$1" in
    --disk) DISKNAME="$2"; shift 2 ;;
    --boot-size) BOOTSIZE="$2"; shift 2 ;;
    --swap-size) SWAPSIZE="$2"; shift 2 ;;
    --no-swap) SWAPSIZE="0"; shift ;;
    --boot-label) BOOT_LABEL="$2"; shift 2 ;;
    --swap-label) SWAP_LABEL="$2"; shift 2 ;;
    --root-label) ROOT_LABEL="$2"; shift 2 ;;
    --luks-label) LUKS_LABEL="$2"; shift 2 ;;
    --encrypt) ENCRYPT="y"; shift ;;
    --no-encrypt) ENCRYPT="n"; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

echo "=== ezpartition: guided disk setup ==="
echo
echo "Available disks:"
lsblk -d -o NAME,SIZE,MODEL,TYPE
echo
if [ -z "$DISKNAME" ]; then
  read -rp "Disk to partition (e.g. sda, nvme0n1): " DISKNAME
fi
DISK="/dev/$DISKNAME"

if [ ! -b "$DISK" ]; then
  echo "No such block device: $DISK" >&2
  exit 1
fi

echo
echo "THIS WILL ERASE ALL DATA ON $DISK."
if [ "$ASSUME_YES" != 1 ]; then
  read -rp "Type the disk name again to confirm ($DISKNAME): " CONFIRM
  if [ "$CONFIRM" != "$DISKNAME" ]; then
    echo "Confirmation didn't match - aborting." >&2
    exit 1
  fi
fi

if [ -z "$ENCRYPT" ]; then
  read -rp "Encrypt the root partition with LUKS? [y/N]: " ENCRYPT
fi
ENCRYPT=$(printf '%s' "$ENCRYPT" | tr '[:upper:]' '[:lower:]')

if [ -z "$BOOTSIZE" ]; then
  read -rp "Boot (ESP) size, e.g. 512M or 1G [512M]: " BOOTSIZE
fi
BOOTSIZE="${BOOTSIZE:-512M}"

if [ -z "$SWAPSIZE" ]; then
  read -rp "Swap size, e.g. 4G or 512M (0 for no swap) [4G]: " SWAPSIZE
fi
SWAPSIZE="${SWAPSIZE:-4G}"

mib_from_size() {
  local input upper num
  input="$1"
  upper=$(printf '%s' "$input" | tr '[:lower:]' '[:upper:]')
  num=$(printf '%s' "$upper" | grep -oE '^[0-9]+')
  case "$upper" in
    *G) echo $(( num * 1024 )) ;;
    *M) echo "$num" ;;
    *) echo "Unrecognized size '$input' - use e.g. 4G or 512M" >&2; exit 1 ;;
  esac
}

partsuffix() {
  case "$DISK" in
    *nvme*|*mmcblk*) echo "p$1" ;;
    *) echo "$1" ;;
  esac
}

swapoff -a || true
umount -R /mnt 2>/dev/null || true
for part in "$DISK"?*; do
  umount "$part" 2>/dev/null || true
done

BOOT_MIB=$(mib_from_size "$BOOTSIZE")
ESP_END=$((1 + BOOT_MIB))
if [ "$SWAPSIZE" = "0" ]; then
  ROOT_START="${ESP_END}MiB"
else
  SWAP_MIB=$(mib_from_size "$SWAPSIZE")
  SWAP_END=$((ESP_END + SWAP_MIB))
  ROOT_START="${SWAP_END}MiB"
fi

echo "Partitioning $DISK (GPT: $BOOTSIZE ESP + $([ "$SWAPSIZE" = "0" ] && echo "no swap" || echo "$SWAPSIZE swap") + root)..."
parted -s "$DISK" -- mklabel gpt
parted -s "$DISK" -- mkpart "$BOOT_LABEL" fat32 1MiB "${ESP_END}MiB"
parted -s "$DISK" -- set 1 esp on
if [ "$SWAPSIZE" != "0" ]; then
  parted -s "$DISK" -- mkpart "$SWAP_LABEL" linux-swap "${ESP_END}MiB" "${SWAP_END}MiB"
  parted -s "$DISK" -- mkpart "$ROOT_LABEL" "$ROOT_START" 100%
else
  parted -s "$DISK" -- mkpart "$ROOT_LABEL" "$ROOT_START" 100%
fi
partprobe "$DISK" || true
udevadm settle

ESP_PART="$DISK$(partsuffix 1)"
if [ "$SWAPSIZE" != "0" ]; then
  SWAP_PART="$DISK$(partsuffix 2)"
  ROOT_PART="$DISK$(partsuffix 3)"
else
  ROOT_PART="$DISK$(partsuffix 2)"
fi

# Clear any leftover filesystem/partition-table signatures on each partition
# before formatting it - mkfs doesn't zero a partition's whole extent (e.g.
# ext4 leaves the first 1024 bytes alone), so stale signatures from whatever
# previously occupied those sectors can make blkid see the device as
# ambiguous and mount refuse it with "wrong fs type, bad option, bad
# superblock" even though the fresh filesystem is otherwise fine.
wipefs -a "$ESP_PART"
mkfs.fat -F32 -n "$BOOT_LABEL" "$ESP_PART"
if [ "$SWAPSIZE" != "0" ]; then
  wipefs -a "$SWAP_PART"
  mkswap -L "$SWAP_LABEL" "$SWAP_PART"
fi

wipefs -a "$ROOT_PART"
if [ "$ENCRYPT" = "y" ] || [ "$ENCRYPT" = "yes" ]; then
  echo "Setting up LUKS on $ROOT_PART (you'll be prompted for a passphrase)..."
  cryptsetup luksFormat "$ROOT_PART"
  cryptsetup luksOpen "$ROOT_PART" "$LUKS_LABEL"
  ROOT_DEV="/dev/mapper/$LUKS_LABEL"
else
  ROOT_DEV="$ROOT_PART"
fi

mkfs.ext4 -L "$ROOT_LABEL" "$ROOT_DEV"

# Writing to a block device via mkfs/mkswap doesn't itself generate a udev
# event, so tools like lsblk that read FSTYPE/LABEL/UUID from udev's cached
# device database (rather than probing live) can keep showing these
# partitions as blank indefinitely after formatting - a plain `blkid
# <dev>` still sees them fine since that's a live probe, but nothing makes
# udev's cache catch up on its own. `udevadm trigger` forces udev to
# re-probe each one; `--settle` after waits for that to finish.
TRIGGER_PARTS=("$ESP_PART" "$ROOT_PART")
if [ "$SWAPSIZE" != "0" ]; then
  TRIGGER_PARTS+=("$SWAP_PART")
fi
udevadm trigger --settle "${TRIGGER_PARTS[@]}"

# Mount with an explicit -t instead of relying on auto-detection: right after
# mkfs, blkid's probe can race with the kernel/udev still settling from the
# format and spuriously report an ambiguous/unrecognized type ("wrong fs
# type, bad option, bad superblock") even though the filesystem is fine -
# skip that probe entirely since we already know what we just formatted.
mount -t ext4 "$ROOT_DEV" /mnt
mkdir -p /mnt/boot
mount -t vfat "$ESP_PART" /mnt/boot
if [ "$SWAPSIZE" != "0" ]; then
  swapon "$SWAP_PART"
fi

echo
echo "Done. Root mounted at /mnt, ESP at /mnt/boot$([ "$SWAPSIZE" != "0" ] && echo ", swap enabled")."
if [ "$ENCRYPT" = "y" ] || [ "$ENCRYPT" = "yes" ]; then
  UUID=$(blkid -s UUID -o value "$ROOT_PART")
  echo "Root is LUKS-encrypted (/dev/mapper/$LUKS_LABEL). Your config needs:"
  echo "  boot.initrd.luks.devices.\"$LUKS_LABEL\".device = \"/dev/disk/by-uuid/$UUID\";"
fi
echo "Now load your config (git clone a flake, or write configuration.nix by hand), use the Hardware config menu to generate hardware-configuration.nix, then click Install NixOS."
