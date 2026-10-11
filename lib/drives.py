#!/usr/bin/env python3
"""List drives that could hold media, one per line, tab-separated:

    device  size  format  label  open-at  uuid  disks

Reads `lsblk --json`, so blank columns can't shift the others. Covers
partitions, unlocked encrypted drives, and filesystems written straight to a
whole disk (common for btrfs pools and some USB drives). A filesystem spread
over several disks (a btrfs pool) is listed once, against its first disk.

Left out: the computer's own drives (anything open somewhere other than
/run/media, /media or /mnt), EFI partitions, swap, encrypted containers that
are still locked, and members of RAID/LVM sets.
"""

import json
import subprocess
import sys

SKIP_FORMATS = {
    "", "swap", "crypto_LUKS", "LVM2_member", "linux_raid_member",
    "zfs_member", "iso9660", "squashfs", "BitLocker",
}
EFI_PARTTYPES = {
    "c12a7328-f81f-11d2-ba4b-00a0c93ec93b",  # GPT EFI system partition
    "0xef",                                  # MBR EFI system partition
}
MEDIA_ROOTS = ("/run/media/", "/media/", "/mnt/")


def human(size):
    size = float(size or 0)
    for unit in ("B", "K", "M", "G", "T", "P"):
        if size < 1024 or unit == "P":
            return f"{size:.1f}{unit}" if unit in ("T", "P") else f"{size:.0f}{unit}"
        size /= 1024
    return "?"


def walk(nodes):
    for node in nodes or []:
        yield node
        yield from walk(node.get("children"))


def clean(text):
    return " ".join(str(text or "").split())[:60]


def main():
    try:
        out = subprocess.run(
            ["lsblk", "--json", "--bytes", "--paths", "-o",
             "NAME,SIZE,FSTYPE,TYPE,LABEL,UUID,MOUNTPOINTS,PARTTYPE"],
            capture_output=True, text=True, timeout=10, check=True,
        ).stdout
        devices = json.loads(out).get("blockdevices", [])
    except (OSError, subprocess.SubprocessError, ValueError):
        return 1

    found = {}
    order = []
    for node in walk(devices):
        fmt = node.get("fstype") or ""
        if node.get("type") not in ("disk", "part", "crypt") or fmt in SKIP_FORMATS:
            continue
        if str(node.get("parttype") or "").lower() in EFI_PARTTYPES:
            continue
        mounts = [m for m in (node.get("mountpoints") or []) if m]
        if any(not m.startswith(MEDIA_ROOTS) for m in mounts):
            continue
        key = node.get("uuid") or node.get("name")
        if key not in found:
            found[key] = {
                "device": node.get("name"),
                "size": node.get("size") or 0,
                "format": fmt,
                "label": clean(node.get("label")),
                "mount": mounts[0] if mounts else "",
                "uuid": node.get("uuid") or "",
                "disks": 0,
            }
            order.append(key)
        entry = found[key]
        entry["disks"] += 1
        if not entry["mount"] and mounts:
            entry["mount"] = mounts[0]

    for key in order:
        e = found[key]
        print("\t".join([
            e["device"], human(e["size"]), e["format"], e["label"] or "-",
            e["mount"] or "-", e["uuid"] or "-", str(e["disks"]),
        ]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
