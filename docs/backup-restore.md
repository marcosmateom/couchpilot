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

### Automate it (cron)

**Cron** is Linux's built-in scheduler: you give it a list of "run this
command at these times" lines, and it runs them forever — even after
reboots, no app needed. Your personal list is edited with `crontab -e`.
To back up every 3 days at 03:00:

1. Open your cron list:

   ```bash
   crontab -e
   ```

   (First time, it may ask which editor to use — pick `nano`, the easiest.)

2. Add this line at the bottom — replacing **both** `/FULL/PATH/TO` with
   where you cloned couchpilot (run `pwd` inside the folder if unsure):

   ```
   0 3 */3 * * /FULL/PATH/TO/couchpilot/scripts/backup.sh >> /FULL/PATH/TO/couchpilot/backup.log 2>&1
   ```

   Reading it left to right: minute `0`, hour `3`, every 3rd day — run the
   backup script and write what happened into `backup.log`.

3. Save and exit (`Ctrl+O`, `Enter`, `Ctrl+X` in nano). Check it took:
   `crontab -l` should show your line.

The newest 3 archives are kept; older ones are pruned automatically. After
the first scheduled run, peek at `backup.log` once to confirm it worked.

## Restore

On a fresh machine (or after a disaster), step by step:

1. **Install Docker** if it's a brand-new machine
   (`curl -fsSL https://get.docker.com | sh`).

2. **Get couchpilot again**:

   ```bash
   git clone https://github.com/marcosmateom/couchpilot.git
   cd couchpilot
   ```

3. **Bring your newest backup file into this folder.** It's the file named
   like `couchpilot-config-20260831-030000.tar.gz.enc` in your `BACKUP_DIR`
   (a USB stick, another drive...). For example, if the backup drive is
   plugged into this machine and mounted:

   ```bash
   cp /mnt/backupdrive/couchpilot-backups/couchpilot-config-*.tar.gz.enc .
   ```

4. **Decrypt and unpack it** — this is one single command split over two
   lines (the `\` joins them); copy the whole thing, then replace the
   filename with your actual file and `YOUR_PASSPHRASE` with your backup
   passphrase:

   ```bash
   openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
     -in couchpilot-config-XXXX.tar.gz.enc -pass pass:YOUR_PASSPHRASE | tar -xzf -
   ```

   No output = success. `bad decrypt` = wrong passphrase.

5. **Start it**: `./mc up`

That's it — `.env` and every app's state land back in place: same logins,
same libraries, same settings. If the media folder lives at a different
path on the new machine, run `./mc setup` once to update it (your other
answers are remembered from the restored `.env`).

## Test your backups

A backup you've never test-restored is a hope, not a backup. Once, on any
machine, run the `openssl ... | tar -xzf -` line into an empty folder and
check the files look right.
