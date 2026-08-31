#!/usr/bin/env bash
# couchpilot uninstaller — run via  ./mc uninstall
# Removes what couchpilot created, in tiers, asking before each one.
# Your MEDIA IS NEVER TOUCHED by this script.

set -euo pipefail
cd "$(dirname "$0")/.."
REPO_DIR="$(pwd)"
MANIFEST=".setup-manifest"
LOG="uninstall.log"

BOLD='\033[1m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; GREEN='\033[0;32m'; NC='\033[0m'
say()  { echo -e "$*"; }
warn() { echo -e "${YELLOW}$*${NC}"; }
log()  { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }

yesno() {
  local __ans
  read -r -p "$(echo -e "${BOLD}$1${NC} [y/N]: ")" __ans || true
  [[ "${__ans:-n}" =~ ^[Yy] ]]
}

# Load .env for DATA_DIR / profiles / COMPOSE_FILE
set -a; source .env 2>/dev/null || true; set +a

echo ""
echo -e "${RED}${BOLD}══════════════════ couchpilot uninstall ══════════════════${NC}"
echo ""
say "This will walk you through removing, in order (asking at each step):"
say "  1. The running containers and docker networks   (always)"
say "     ...then optionally docker volumes and images"
say "  2. Generated config: .env, compose overrides, Caddy/Pi-hole files"
say "  3. ${RED}App state: */config dirs — your app settings, watch history,${NC}"
say "     ${RED}indexer configs, Pi-hole lists, Tailscale login. GONE forever.${NC}"
say ""
say "  ${GREEN}Your media (${DATA_DIR:-your media folder}) is NEVER deleted.${NC}"
say ""
if [[ ! -f "$MANIFEST" ]]; then
  warn "No .setup-manifest found — running in known-paths mode (same coverage,"
  warn "just without the per-run detail). Nothing outside this folder is touched."
fi
read -r -p "$(echo -e "Type ${BOLD}uninstall${NC} to continue, anything else aborts: ")" confirm
[[ "$confirm" == "uninstall" ]] || { say "Aborted — nothing was changed."; exit 0; }

log "Uninstall started in $REPO_DIR"

# ── Tier 1: containers, networks, volumes, images ─────────────────────────────
say ""
say "${BOLD}Tier 1 — stopping the stack${NC}"
COMPOSE_PROFILES='*' docker compose down --remove-orphans 2>/dev/null \
  || docker compose down --remove-orphans || true
log "docker compose down --remove-orphans (all profiles)"

if yesno "Also remove docker volumes (Caddy's certificates) and built images?"; then
  COMPOSE_PROFILES='*' docker compose down --volumes --rmi local 2>/dev/null || true
  docker image prune -f --filter "dangling=true" &>/dev/null || true
  log "removed docker volumes + local images"
fi

# ── Tier 2: generated files ───────────────────────────────────────────────────
say ""
say "${BOLD}Tier 2 — generated configuration${NC}"
gen_files=(.env compose.hwaccel.yml compose.drives.yml)
while IFS= read -r f; do gen_files+=("$f"); done < <(ls caddy/sites/*.caddy 2>/dev/null || true)
[[ -f pihole/etc-pihole/hosts/local-dns.list ]] && gen_files+=(pihole/etc-pihole/hosts/local-dns.list)
existing=()
for f in "${gen_files[@]}"; do [[ -e "$f" ]] && existing+=("$f"); done
if [[ ${#existing[@]} -gt 0 ]]; then
  say "Would remove: ${existing[*]}"
  if yesno "Remove generated configuration?"; then
    for f in "${existing[@]}"; do rm -f "$f"; log "removed $f"; done
    rm -f "$MANIFEST" && log "removed $MANIFEST" || true
  fi
else
  say "None found — skipping."
fi

# ── Tier 3: app state ─────────────────────────────────────────────────────────
say ""
say "${BOLD}Tier 3 — app state (the dangerous one)${NC}"
state_dirs=()
for d in */config; do [[ -d "$d" ]] && state_dirs+=("$d"); done
for d in pihole/etc-pihole tailscale/state jellyfin/cache; do
  [[ -d "$d" ]] && state_dirs+=("$d")
done
if [[ ${#state_dirs[@]} -gt 0 ]]; then
  say "Would remove: ${state_dirs[*]}"
  warn "This is every app's database: Jellyfin users & watch history, Sonarr/"
  warn "Radarr libraries, qBittorrent torrents, Pi-hole lists, Tailscale login."
  warn "Consider running scripts/backup.sh first."
  if yesno "PERMANENTLY delete all app state?"; then
    for d in "${state_dirs[@]}"; do rm -rf "$d"; log "removed $d"; done
    # Clean now-empty parent dirs (never the repo's tracked dirs)
    for d in jellyfin sonarr radarr bazarr prowlarr qbittorrent jellyseerr \
             jackett rdtclient suwayomi komga pihole tailscale; do
      rmdir "$d" 2>/dev/null && log "removed empty dir $d" || true
    done
  fi
else
  say "None found — skipping."
fi

# ── Media report (never deleted) ──────────────────────────────────────────────
say ""
if [[ -n "${DATA_DIR:-}" ]]; then
  say "${GREEN}Untouched (your media):${NC} $DATA_DIR"
  [[ -n "${EXTRA_DRIVES:-}" ]] && say "${GREEN}Untouched (extra drives):${NC} $EXTRA_DRIVES"
  [[ -n "${MANGA_DIR:-}" ]] && say "${GREEN}Untouched (manga):${NC} $MANGA_DIR"
fi

# ── Cron entries referencing this repo ────────────────────────────────────────
if crontab -l 2>/dev/null | grep -qF "$REPO_DIR"; then
  say ""
  say "Found cron entries referencing this folder:"
  crontab -l | grep -F "$REPO_DIR" | sed 's/^/  /'
  if yesno "Remove them from your crontab?"; then
    crontab -l | grep -vF "$REPO_DIR" | crontab -
    log "removed crontab entries referencing $REPO_DIR"
  fi
fi

say ""
say "${GREEN}Done.${NC} A record of what was removed is in $LOG."
say "To finish removing couchpilot entirely, delete this folder:"
say "  rm -rf $REPO_DIR"
