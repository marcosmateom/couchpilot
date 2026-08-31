#!/usr/bin/env bash
# couchpilot config backup — encrypted snapshot of everything you'd need to
# rebuild your setup (NOT your media — that's too big; see docs/backup-restore.md).
#
# Needs in .env:   BACKUP_DIR         where archives go (ideally another drive)
#                  BACKUP_PASSPHRASE  encryption passphrase (don't lose it!)
#
# Run it by hand or via cron, e.g. every 3 days at 03:00:
#   0 3 */3 * * /path/to/couchpilot/scripts/backup.sh >> /path/to/couchpilot/backup.log 2>&1

set -euo pipefail
cd "$(dirname "$0")/.."

KEEP=3
STAMP="$(date +%Y%m%d-%H%M%S)"

BACKUP_DIR="$(grep -oP '^BACKUP_DIR=\K.*' .env 2>/dev/null || true)"
BACKUP_PASSPHRASE="$(grep -oP '^BACKUP_PASSPHRASE=\K.*' .env 2>/dev/null || true)"

if [[ -z "$BACKUP_DIR" || -z "$BACKUP_PASSPHRASE" ]]; then
  echo "ERROR: set BACKUP_DIR and BACKUP_PASSPHRASE in .env first." >&2
  echo "See the 'Backups' section of .env.example." >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
umask 077

# Collect what exists: secrets, generated files, and every service's state
targets=(.env)
for f in compose.hwaccel.yml compose.drives.yml .setup-manifest; do
  [[ -e "$f" ]] && targets+=("$f")
done
[[ -d caddy/sites ]] && targets+=(caddy/sites)
[[ -d pihole/etc-pihole ]] && targets+=(pihole/etc-pihole)
[[ -d tailscale/state ]] && targets+=(tailscale/state)
for d in */config; do
  [[ -d "$d" ]] && targets+=("$d")
done

OUT="$BACKUP_DIR/couchpilot-config-$STAMP.tar.gz.enc"
echo "[$(date '+%F %T')] Backing up ${#targets[@]} paths → $OUT"

export BACKUP_PASSPHRASE
tar -czf - \
  --exclude='*/listsCache' \
  --exclude='*/transcodes' \
  --exclude='*/cache' \
  --exclude='*/logs' \
  --exclude='*.log' \
  "${targets[@]}" \
  | openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -salt \
      -pass env:BACKUP_PASSPHRASE -out "$OUT"

echo "[$(date '+%F %T')] Done: $(du -h "$OUT" | cut -f1)"

# Keep only the newest $KEEP archives
ls -1t "$BACKUP_DIR"/couchpilot-config-*.tar.gz.enc 2>/dev/null \
  | tail -n +$((KEEP+1)) \
  | while read -r old; do
      echo "[$(date '+%F %T')] Pruning $old"
      rm -f "$old"
    done
