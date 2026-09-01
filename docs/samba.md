# File sharing (Samba)

The `samba` profile shares your media folder over the network so you can
drag-and-drop files from Windows/macOS — handy for music, photos, or media
you acquired outside the *arr apps.

## What the wizard sets up

When you answer **y** to Samba in `./mc setup`, the wizard only asks for a
**username and password** (that's all it stores, in `.env`). The share
itself is already defined in `docker-compose.yml` and is the same for every
couchpilot install:

- **One share, always named `Data`** — it contains your whole media folder
  (`DATA_DIR`), so `movies/`, `tv/`, `downloads/` are inside it.
- Extra drives added in the wizard appear inside that same share as
  `data2/`, `data3/`, ...

Nothing to configure, nothing to name — after `./mc up` the share just
exists.

## Connecting, step by step

You'll need: your **server's IP** (`./mc ip` shows it — say it's
`192.168.1.50` in the examples below) and the **Samba username/password**
from setup (not your qBittorrent or Jellyfin login — Samba has its own).

**Windows:**

1. Open **File Explorer** (the folder icon).
2. Click into the **address bar** at the top and type two backslashes plus
   the server IP: `\\192.168.1.50` → press Enter.
3. A login box appears: enter the Samba username and password, tick
   **Remember my credentials** → OK.
4. You'll see the `Data` folder — double-click in, drag files as if it were
   a normal folder.
5. Want it to show up as a drive letter permanently? Right-click `Data` →
   **Map network drive...** → pick a letter → tick "Reconnect at sign-in"
   → Finish. From now on it's just there, next to `C:`.

**macOS:**

1. In Finder: **Go → Connect to Server** (or press `Cmd+K`).
2. Type `smb://192.168.1.50` → Connect.
3. Log in with the Samba username/password, pick the `Data` share.

**Linux:**

- File manager: **Other Locations** → enter `smb://192.168.1.50/Data`.
- Or from a terminal:
  `sudo mount -t cifs //192.168.1.50/Data /mnt/share -o username=YOUR_SAMBA_USER`

**Over Tailscale**, the same steps work from anywhere — just use the
Tailscale IP instead: `\\100.x.y.z` (`./mc ip` shows it too).

## Adding more shares (advanced)

First, you may not need to: **anything inside your media folder is already
shared** — create a subfolder (`Data/photos`, `Data/music`...) and it's
instantly reachable by everyone. And wizard-added extra drives are in there
too (`data2/`, ...).

A truly *separate* share (a folder outside `DATA_DIR`, or one with
different permissions) needs a custom Samba config, because the
`dockurr/samba` image only defines its single env-based share:

1. Get the current config out of the container as a starting point:

   ```bash
   docker exec samba cat /etc/samba/smb.conf > samba-custom.conf
   ```

2. Edit `samba-custom.conf` and add a block per new share at the bottom,
   copying the style of the existing `[Data]` block, e.g.:

   ```ini
   [photos]
   path = /photos
   browseable = yes
   read only = no
   ```

3. In `docker-compose.yml`, under the `samba:` service, mount both the
   config and the new folder:

   ```yaml
   volumes:
     # ...existing Data mount stays...
     - ./samba-custom.conf:/etc/samba/smb.conf
     - /path/on/your/server/photos:/photos
   ```

4. `./mc up` — the new share appears next to `Data`.

## Notes

- Files you copy in are owned by your PUID/PGID, so Jellyfin and the *arrs
  can read them immediately.
- The share survives host drive remounts (power cuts) automatically thanks
  to `rslave` bind propagation — no restart needed.
- Samba is for your LAN/tailnet only. **Never** port-forward 445 on your
  router to the internet.
