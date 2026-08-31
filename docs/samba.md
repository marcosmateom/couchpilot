# File sharing (Samba)

The `samba` profile shares your media folder over the network so you can
drag-and-drop files from Windows/macOS — handy for music, photos, or media
you acquired outside the *arr apps.

Enable it in `./mc setup` (pick a username + password). The share is called
**Data** and contains your whole media folder.

## Connecting

- **Windows**: Explorer → address bar → `\\SERVER-IP\Data`
  (or Map Network Drive for a permanent letter). Log in with the Samba
  username/password from setup.
- **macOS**: Finder → Go → Connect to Server → `smb://SERVER-IP/Data`
- **Linux**: Files → Other Locations → `smb://SERVER-IP/Data`,
  or `sudo mount -t cifs //SERVER-IP/Data /mnt/share -o username=...`

Over Tailscale the same works with the Tailscale IP: `\\100.x.y.z\Data`.

## Notes

- Files you copy in are owned by your PUID/PGID, so Jellyfin and the *arrs
  can read them immediately.
- Extra drives from the wizard appear inside the share as `data2/`, `data3/`.
- The share survives host drive remounts (power cuts) automatically thanks
  to `rslave` bind propagation — no restart needed.
- Samba here is LAN/tailnet-only. Do not port-forward 445 to the internet,
  ever.
