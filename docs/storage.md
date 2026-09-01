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

## Which folder should I pick in the wizard?

Depends on what disks the machine has:

- **One disk only** (typical old PC or laptop): the default `~/media` is
  right. Just know movies are big — keep an eye on free space with
  `df -h ~` (look at the "Avail" column) so the disk doesn't fill up.
- **A small system disk + a big data disk** (typical home-server build):
  put media on the **big** one — mount it (next section) and give the
  wizard that path, e.g. `/mnt/media`. If you put media on the small system
  disk instead, it fills up, and a full system disk causes weird, seemingly
  unrelated problems ("no space left" errors, apps refusing to start,
  updates failing) — that's the trap this section exists to avoid.

Not sure what you have? `lsblk` lists every disk with its size — one line
starting with `sd`/`nvme` per physical disk.

## Using a dedicated drive

This section applies to **any drive you added yourself** — a second internal
disk *or* an external USB drive. It works the same for both, and both need
it: Linux only mounts at boot what the OS installer set up (your system
disk); anything added later is invisible until you mount it.

> **"But my USB drive just works when I plug it in!"** — on a desktop, the
> file manager auto-mounts it *when you click it*, at a path that can
> change, and only while you're logged in. At boot — which is when the
> couchpilot containers start — it isn't mounted, and the apps would see an
> empty folder. That's why even external drives get the fstab treatment
> below on a server.

Mount the drive first, then point the wizard at it. First find the drive's
name:

```bash
lsblk -f
```

You'll see something like this:

```
NAME        FSTYPE  LABEL    UUID                                  ...
sda
├─sda1      vfat             1234-ABCD
└─sda2      ext4             abcd1234-ee11-4c02-9f33-aabbccddeeff
sdb
└─sdb1      ext4    bigdisk  f00dcafe-2222-4d44-b555-123456789abc
```

`sda`, `sdb`... are your disks; `sda1`, `sdb1`... are the partitions on
them. **`sdX1` in guides is a placeholder — there is no actual sdX.** Find
*your* drive by its size (`lsblk` without `-f` shows sizes) or its LABEL —
here the 4 TB media drive is `sdb1`. Then:

```bash
sudo mkdir -p /mnt/media
sudo mount /dev/sdb1 /mnt/media        # ← use YOUR partition name, not sdb1
./mc setup                             # answer /mnt/media for the media folder
```

### Mount it automatically at boot (fstab)

A manual `mount` disappears on reboot — after which the folder is just
empty and everything looks broken. `/etc/fstab` is the file Linux reads at
boot to know what to mount where; one line per drive. Step by step:

1. Get the drive's UUID (a unique ID that never changes, unlike `sdb1`
   which can shuffle between boots) and its filesystem type:

   ```bash
   lsblk -f
   ```

   From the example above: UUID `f00dcafe-2222-4d44-b555-123456789abc`,
   FSTYPE `ext4`.

2. Open fstab in an editor:

   ```bash
   sudo nano /etc/fstab
   ```

3. Add **one line at the bottom** (arrow keys to move; replace the UUID and
   the `ext4` with yours from step 1 — the rest is copy-paste):

   ```
   UUID=f00dcafe-2222-4d44-b555-123456789abc  /mnt/media  ext4  defaults,nofail,x-systemd.device-timeout=5s  0  2
   ```

   The `nofail` + timeout part means that if the drive is ever missing or
   dead, your machine **still boots normally** instead of hanging — always
   worth having on a secondary drive.

4. Save and exit nano: `Ctrl+O`, `Enter`, `Ctrl+X`.

5. Test it **now, before rebooting** (a typo in fstab is much nicer to
   discover here than at boot):

   ```bash
   sudo mount -a
   ```

   No output = all good. An error names the line that's wrong.

## Multiple drives

The wizard's "extra drive" question mounts each additional path into the
apps as `/data2`, `/data3`, ... — each with its own `movies/ tv/ downloads/`
tree, so hardlinks keep working *within* each drive.

Each extra drive needs mounting at boot too: repeat the
[fstab steps above](#mount-it-automatically-at-boot-fstab) once per drive —
its own UUID, its own mount point (`/mnt/media2`, `/mnt/media3`, ...), one
line each in `/etc/fstab`. Then, inside the apps:

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
