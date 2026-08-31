# Backup & restore

`scripts/backup.sh` snapshots everything needed to rebuild your setup —
`.env`, generated config, and every app's state (Jellyfin users & watch
history, Sonarr/Radarr libraries, qBittorrent torrents, Pi-hole lists,
Tailscale login) — into **one encrypted file**. Your media itself is *not*
included (too big; media is what the stack can re-download, your config is
what it can't).

## Setup

Add to `.env`:

```
BACKUP_DIR=/mnt/otherdrive/couchpilot-backups   # ideally NOT the same drive
BACKUP_PASSPHRASE=pick-a-long-passphrase        # lose it = backups useless
```

Run one now: `bash scripts/backup.sh`

Automate it (every 3 days at 03:00) with `crontab -e`:

```
0 3 */3 * * /FULL/PATH/TO/couchpilot/scripts/backup.sh >> /FULL/PATH/TO/couchpilot/backup.log 2>&1
```

The newest 3 archives are kept; older ones are pruned automatically.

## Restore

On a fresh machine (or after a disaster):

```bash
git clone <your-couchpilot-repo> && cd couchpilot
# copy your newest couchpilot-config-*.tar.gz.enc here, then:
openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
  -in couchpilot-config-XXXX.tar.gz.enc -pass pass:YOUR_PASSPHRASE | tar -xzf -
./mc up
```

That's it — `.env` and every app's state land back in place. If the media
folder path differs on the new machine, run `./mc setup` once to update it
(your other answers are remembered from the restored `.env`).

## Test your backups

A backup you've never test-restored is a hope, not a backup. Once, on any
machine, run the `openssl ... | tar -xzf -` line into an empty folder and
check the files look right.
