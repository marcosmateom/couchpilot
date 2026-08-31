# Storage: layout, hardlinks, drives

## The layout

Everything lives under one folder (`DATA_DIR`, default `~/media`):

```
media/
├── movies/       Radarr's library — Jellyfin's Movies folder is /data/movies
├── tv/           Sonarr's library — Jellyfin's Shows folder is /data/tv
├── downloads/
│   ├── complete/     finished downloads land here
│   └── incomplete/   in-progress downloads
└── manga/        (only with the manga profile)
```

Every container sees this same folder as `/data`. That single detail is why
imports are **instant**: when Sonarr moves a finished download into the
library, both paths are on the same filesystem, so it creates a *hardlink* —
the file isn't copied, it just gains a second name. Zero extra disk space,
zero copy time, and you can keep seeding the original.

If downloads and library were on different drives (or different Docker
mounts), every import would be a full copy. That's the mistake this layout
exists to avoid — and why you shouldn't "just add a volume" by hand.

## Using a dedicated drive

Mount the drive first, then point the wizard at it:

```bash
sudo mkdir -p /mnt/media
sudo mount /dev/sdX1 /mnt/media        # find yours with: lsblk -f
./mc setup                             # answer /mnt/media for the media folder
```

### Mount it automatically at boot (fstab)

A manual `mount` disappears on reboot. For a permanent setup, add the drive
to `/etc/fstab` by UUID:

```bash
lsblk -f                               # note the drive's UUID and fstype
sudo nano /etc/fstab
```

Add one line (replace UUID and fstype with yours):

```
UUID=xxxxxxxx-xxxx-...  /mnt/media  ext4  defaults,nofail,x-systemd.device-timeout=5s  0  2
```

- `nofail` + the timeout mean a missing/dead drive **won't hang your boot** —
  worth having on any secondary drive.
- Test with `sudo mount -a` (no errors = good) **before** rebooting.

## Multiple drives

The wizard's "extra drive" question mounts each additional path into the
apps as `/data2`, `/data3`, ... — each with its own `movies/ tv/ downloads/`
tree, so hardlinks keep working *within* each drive:

- In **Sonarr/Radarr**, add `/data2/tv` or `/data2/movies` as an extra root
  folder.
- In **Jellyfin**, add `/data2/movies` (etc.) to the existing libraries.
- In **qBittorrent**, create a category whose save path is
  `/data2/downloads/complete` for content that should live on that drive
  (a download must land on the same drive as its library to hardlink).
- With **Samba**, extra drives appear inside the share as `data2/`, `data3/`.

## When a drive goes missing

If a mounted drive disappears (unplugged, died, failed to mount after a
power cut), the containers just see an **empty folder** at its path. Symptoms:
libraries look empty, downloads may silently fill your root filesystem.

```bash
df -h /path/to/drive     # shows the drive, or "/" if it's not mounted
sudo mount -a            # remount everything in fstab
./mc restart             # let the apps re-scan
```

This is host-level plumbing on purpose — couchpilot consumes paths, it never
touches your fstab or partitions.
