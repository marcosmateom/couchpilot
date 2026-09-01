#!/usr/bin/env bash
# couchpilot setup wizard — run via  ./mc setup
# Safe to re-run any time: existing answers become the new defaults, and all
# generated files are rebuilt from scratch.

set -euo pipefail
cd "$(dirname "$0")/.."
REPO_DIR="$(pwd)"
MANIFEST=".setup-manifest"

BOLD='\033[1m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
say()    { echo -e "$*"; }
title()  { echo -e "\n${BOLD}${CYAN}$*${NC}"; }
warn()   { echo -e "${YELLOW}$*${NC}"; }
fail()   { echo -e "${RED}$*${NC}"; exit 1; }

# ── Small helpers ─────────────────────────────────────────────────────────────

# ask VAR "Question" "default"
ask() {
  local __var="$1" __q="$2" __def="${3:-}" __ans
  if [[ -n "$__def" ]]; then
    read -r -p "$(echo -e "${BOLD}${__q}${NC} [${__def}]: ")" __ans || true
    __ans="${__ans:-$__def}"
  else
    read -r -p "$(echo -e "${BOLD}${__q}${NC}: ")" __ans || true
  fi
  printf -v "$__var" '%s' "$__ans"
}

# yesno "Question" "y"|"n"  → returns 0 for yes
yesno() {
  local __q="$1" __def="${2:-n}" __hint __ans
  [[ "$__def" == "y" ]] && __hint="Y/n" || __hint="y/N"
  read -r -p "$(echo -e "${BOLD}${__q}${NC} [${__hint}]: ")" __ans || true
  __ans="${__ans:-$__def}"
  [[ "$__ans" =~ ^[Yy] ]]
}

gen_password() {
  if command -v openssl &>/dev/null; then
    openssl rand -base64 12 | tr -d '/+=' | head -c 16
  else
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16
  fi
}

expand_tilde() { printf '%s' "${1/#\~/$HOME}"; }

manifest_add() {
  local line="$1"
  grep -qxF "$line" "$MANIFEST" 2>/dev/null || echo "$line" >> "$MANIFEST"
}

# mkdir that records whether it created or found the directory
mkdir_logged() {
  local d="$1"
  if [[ -d "$d" ]]; then
    manifest_add "found-dir $d"
  else
    mkdir -p "$d"
    manifest_add "created-dir $d"
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
title "couchpilot setup"
say "A few questions and you're done. Press Enter to accept the [default]."
say "Re-running this wizard later is always safe — it remembers your answers."

# ── 0. Preflight ──────────────────────────────────────────────────────────────
title "Checking your system..."

if [[ "$(uname -s)" != "Linux" ]]; then
  fail "couchpilot runs on Linux only.
On Windows or macOS, run it inside a Linux virtual machine instead.
(WSL2 might work but is unsupported — too many things behave differently.)"
fi

if ! command -v docker &>/dev/null; then
  warn "Docker is not installed."
  say  "The official installer is:  curl -fsSL https://get.docker.com | sh"
  if yesno "Run it now?" "n"; then
    curl -fsSL https://get.docker.com | sh
    manifest_add "installed docker (get.docker.com)"
  else
    fail "Install Docker first, then re-run ./mc setup"
  fi
fi

if ! docker compose version &>/dev/null; then
  fail "Docker Compose v2 is missing (the 'docker compose' plugin).
If you installed Docker from your distro's repos, install the
docker-compose-plugin package, or reinstall via: curl -fsSL https://get.docker.com | sh"
fi

if ! docker info &>/dev/null; then
  if ! systemctl is-active --quiet docker 2>/dev/null; then
    fail "The Docker daemon is not running. Start it with:
  sudo systemctl enable --now docker
then re-run ./mc setup"
  fi
  warn "You can't talk to Docker without sudo."
  if yesno "Add $USER to the docker group now (needs sudo)?" "y"; then
    sudo usermod -aG docker "$USER"
    manifest_add "usermod-docker-group $USER"
    fail "Done — now log out and back in (or run 'newgrp docker'), then re-run ./mc setup"
  else
    fail "Fix Docker permissions first, then re-run ./mc setup"
  fi
fi
say "${GREEN}System looks good.${NC}"

# Load previous answers as defaults (re-run support)
if [[ -f .env ]]; then
  set -a; source .env; set +a
  say "Found an existing .env — your previous answers are the defaults."
fi

# ── 1. Timezone ───────────────────────────────────────────────────────────────
title "1/8  Timezone"
tz_detect="$(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo UTC)"
ask TZ "Timezone" "${TZ:-$tz_detect}"

# ── 2. Media folder(s) ────────────────────────────────────────────────────────
title "2/8  Media storage"
say "One folder holds everything: movies/, tv/ and downloads/ live inside it"
say "so imports are instant (hardlinks) instead of slow copies."
ask DATA_DIR "Media folder" "${DATA_DIR:-$HOME/media}"
DATA_DIR="$(expand_tilde "$DATA_DIR")"
mkdir_logged "$DATA_DIR"
for sub in movies tv downloads/complete downloads/incomplete; do
  mkdir_logged "$DATA_DIR/$sub"
done
if ! mountpoint -q "$DATA_DIR" 2>/dev/null; then
  fs_dev="$(df --output=target "$DATA_DIR" 2>/dev/null | tail -1)"
  if [[ "$fs_dev" == "/" ]]; then
    warn "Note: $DATA_DIR is on your main system disk. That's fine if this"
    warn "machine only has one disk — just keep an eye on free space. If your"
    warn "media should live on a separate/bigger drive, set that drive up"
    warn "first (docs/storage.md explains how) and re-run setup."
  fi
fi

EXTRA_DRIVES_NEW=""
extra_defaults=(${EXTRA_DRIVES:-})
idx=2
say ""
say "You can add more drives — each shows up in the apps as /data2, /data3, ..."
while true; do
  def="${extra_defaults[$((idx-2))]:-}"
  if [[ -n "$def" ]]; then
    if ! yesno "Keep extra drive #$((idx-1)) ($def)?" "y"; then def=""; fi
  fi
  if [[ -z "$def" ]]; then
    if ! yesno "Add an extra media drive/folder?" "n"; then break; fi
    ask def "Path of extra drive #$((idx-1))" ""
    [[ -z "$def" ]] && break
  fi
  def="$(expand_tilde "$def")"
  mkdir_logged "$def"
  for sub in movies tv downloads/complete downloads/incomplete; do
    mkdir_logged "$def/$sub"
  done
  if ! mountpoint -q "$def" 2>/dev/null; then
    warn "  Heads-up: no drive seems to be mounted at $def right now — if it's"
    warn "  supposed to be one, docs/storage.md shows how to set that up."
  fi
  EXTRA_DRIVES_NEW="${EXTRA_DRIVES_NEW:+$EXTRA_DRIVES_NEW }$def"
  idx=$((idx+1))
done
EXTRA_DRIVES="$EXTRA_DRIVES_NEW"

# ── 3. User / permissions ─────────────────────────────────────────────────────
title "3/8  File ownership"
say "The apps run as your user so files aren't owned by root. The detected"
say "values below are right for almost everyone — just press Enter twice."
ask PUID "User ID" "${PUID:-$(id -u)}"
ask PGID "Group ID" "${PGID:-$(id -g)}"
owner_uid="$(stat -c %u "$DATA_DIR" 2>/dev/null || echo "$PUID")"
if [[ "$owner_uid" != "$PUID" ]]; then
  warn "Note: your media folder belongs to a different user (id $owner_uid)."
  warn "Make it yours with:  sudo chown -R $PUID:$PGID $DATA_DIR"
fi

# ── 4. Hardware transcoding ───────────────────────────────────────────────────
title "4/8  Hardware transcoding (Jellyfin)"
HWACCEL="${HWACCEL:-none}"
RENDER_GID="${RENDER_GID:-}"
gpu_option=""; gpu_label=""
for node in /dev/dri/renderD*; do
  [[ -e "$node" ]] || continue
  vendor="$(cat "/sys/class/drm/$(basename "$node")/device/vendor" 2>/dev/null || echo "")"
  case "$vendor" in
    0x8086) gpu_option="vaapi"; gpu_label="Intel GPU detected → QuickSync" ;;
    0x1002) gpu_option="vaapi"; gpu_label="AMD GPU detected → VAAPI" ;;
    *)      gpu_option="vaapi"; gpu_label="GPU render node detected → VAAPI" ;;
  esac
  RENDER_GID="$(stat -c %g "$node")"
  break
done
if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
  if docker info 2>/dev/null | grep -qi nvidia; then
    gpu_option="nvidia"; gpu_label="NVIDIA GPU detected → NVENC"
  else
    warn "NVIDIA GPU found, but the NVIDIA Container Toolkit is not set up in"
    warn "Docker — using CPU for now. See docs/hardware-transcoding.md, then re-run setup."
    gpu_option=""; gpu_label=""
  fi
fi
if [[ -n "$gpu_option" ]]; then
  say "$gpu_label"
  say "  1) Use the GPU for transcoding (recommended — much faster, less power)"
  say "  2) CPU only"
  hw_def="1"; [[ "$HWACCEL" == "none" && -f .env ]] && hw_def="2"
  ask hw_choice "Choose" "$hw_def"
  if [[ "$hw_choice" == "1" ]]; then HWACCEL="$gpu_option"; else HWACCEL="none"; fi
else
  say "No usable GPU detected — Jellyfin will transcode on the CPU (fine for"
  say "most setups; direct play doesn't transcode at all)."
  HWACCEL="none"
fi

# ── 5. Optional features ──────────────────────────────────────────────────────
in_profiles() { [[ ",${COMPOSE_PROFILES:-}," == *",$1,"* ]]; }
profiles=""

title "5/8  Network-wide ad blocking (Pi-hole + Unbound)"
say "Blocks ads on every device at home by acting as your network's DNS server."
if yesno "Enable Pi-hole ad blocking?" "$(in_profiles dns && echo y || echo n)"; then
  profiles="dns"
  lan_detect="$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || hostname -I | awk '{print $1}')"
  ask LAN_IP "This machine's LAN IP" "${LAN_IP:-$lan_detect}"
  PIHOLE_PASSWORD="${PIHOLE_PASSWORD:-$(gen_password)}"
  ask PIHOLE_PASSWORD "Pi-hole web password" "$PIHOLE_PASSWORD"
fi

title "6/8  Extras"
say "Manga: Suwayomi fetches chapters automatically, Komga is the reader."
if yesno "Enable the manga stack?" "$(in_profiles manga && echo y || echo n)"; then
  profiles="${profiles:+$profiles,}manga"
  MANGA_DIR="${MANGA_DIR:-$DATA_DIR/manga}"
  ask MANGA_DIR "Manga folder" "$MANGA_DIR"
  MANGA_DIR="$(expand_tilde "$MANGA_DIR")"
  mkdir_logged "$MANGA_DIR"
  ask SUWAYOMI_USER "Suwayomi username" "${SUWAYOMI_USER:-$USER}"
  SUWAYOMI_PASSWORD="${SUWAYOMI_PASSWORD:-$(gen_password)}"
  ask SUWAYOMI_PASSWORD "Suwayomi password" "$SUWAYOMI_PASSWORD"
fi

say ""
say "Samba shares your media folder with Windows/macOS (\\\\server-ip\\Data)."
if yesno "Enable Windows file sharing (Samba)?" "$(in_profiles samba && echo y || echo n)"; then
  profiles="${profiles:+$profiles,}samba"
  ask SAMBA_USER "Samba username" "${SAMBA_USER:-$USER}"
  SAMBA_PASSWORD="${SAMBA_PASSWORD:-$(gen_password)}"
  ask SAMBA_PASSWORD "Samba password" "$SAMBA_PASSWORD"
fi

title "7/8  Remote access (Tailscale)"
say "Tailscale is a free personal VPN — your phone/laptop can reach every"
say "service from anywhere, same URLs, no ports opened on your router."
ts_default="$(in_profiles tailscale && echo y || echo n)"
if pgrep -x tailscaled &>/dev/null && ! in_profiles tailscale; then
  warn "tailscaled is already running on this machine — you don't need the"
  warn "container. Skipping (your host Tailscale already provides remote access)."
elif yesno "Enable Tailscale?" "$ts_default"; then
  profiles="${profiles:+$profiles,}tailscale"
  say "Get an auth key at https://login.tailscale.com/admin/settings/keys"
  say "(or leave blank — you'll get a login link in './mc logs tailscale')"
  ask TS_AUTHKEY "Tailscale auth key (optional)" "${TS_AUTHKEY:-}"
  ask TS_HOSTNAME "Machine name on your tailnet" "${TS_HOSTNAME:-couchpilot}"
fi

# jackett / rdtclient: docs-only, keep the flow short — preserve if present
in_profiles jackett   && profiles="${profiles:+$profiles,}jackett"
in_profiles rdtclient && profiles="${profiles:+$profiles,}rdtclient"

title "8/8  Custom domain with HTTPS (optional)"
say "With a domain (managed on Cloudflare) you get https://jellyfin.yourdomain.com"
say "style URLs with real certificates. Totally optional — everything works"
say "without one at http://server-ip:port. Guide: docs/domain-https.md"
if yesno "Set up a domain now?" "$([[ -n "${DOMAIN:-}" ]] && echo y || echo n)"; then
  ask DOMAIN "Your domain (e.g. example.com)" "${DOMAIN:-}"
  say "Token: Cloudflare dashboard → My Profile → API Tokens → Create Token"
  say "→ 'Edit zone DNS' template, scoped to $DOMAIN (needs Zone:Read + DNS:Edit)"
  ask CLOUDFLARE_API_TOKEN "Cloudflare API token" "${CLOUDFLARE_API_TOKEN:-}"
else
  DOMAIN=""; CLOUDFLARE_API_TOKEN=""
fi

# ── Summary ───────────────────────────────────────────────────────────────────
case "$HWACCEL" in
  vaapi)  hw_human="GPU (Intel/AMD)" ;;
  nvidia) hw_human="GPU (NVIDIA)" ;;
  *)      hw_human="CPU only" ;;
esac
title "Summary"
say "  Timezone:        $TZ"
say "  Media folder:    $DATA_DIR"
[[ -n "$EXTRA_DRIVES" ]] && say "  Extra drives:    $EXTRA_DRIVES"
say "  Runs as user:    $PUID:$PGID"
say "  Transcoding:     $hw_human"
say "  Extras:          ${profiles:-none}"
say "  Domain:          ${DOMAIN:-none (access via http://server-ip:port)}"
say ""
if ! yesno "Write this configuration?" "y"; then
  fail "Nothing written. Re-run ./mc setup whenever you like."
fi

# ── Write .env ────────────────────────────────────────────────────────────────
COMPOSE_PROFILES="$profiles"

# Build the COMPOSE_FILE chain from the overrides we'll generate
compose_chain="docker-compose.yml"
[[ "$HWACCEL" != "none" ]] && compose_chain="$compose_chain:compose.hwaccel.yml"
[[ -n "$EXTRA_DRIVES" ]] && compose_chain="$compose_chain:compose.drives.yml"

{
  echo "# couchpilot configuration — generated by ./mc setup on $(date -u +%Y-%m-%d)"
  echo "# Re-run ./mc setup to change anything (it remembers these answers)."
  echo ""
  echo "TZ=$TZ"
  echo "PUID=$PUID"
  echo "PGID=$PGID"
  echo "DATA_DIR=$DATA_DIR"
  echo "COMPOSE_PROFILES=$COMPOSE_PROFILES"
  [[ "$compose_chain" != "docker-compose.yml" ]] && echo "COMPOSE_FILE=$compose_chain"
  echo ""
  echo "# Wizard bookkeeping"
  echo "HWACCEL=$HWACCEL"
  [[ -n "${RENDER_GID:-}" ]] && echo "RENDER_GID=$RENDER_GID"
  [[ -n "$EXTRA_DRIVES" ]] && echo "EXTRA_DRIVES=$EXTRA_DRIVES"
  if [[ -n "${LAN_IP:-}" ]]; then
    echo ""
    echo "# Pi-hole (dns profile)"
    echo "LAN_IP=$LAN_IP"
    echo "PIHOLE_PASSWORD=$PIHOLE_PASSWORD"
  fi
  if [[ -n "${DOMAIN:-}" ]]; then
    echo ""
    echo "# Domain mode"
    echo "DOMAIN=$DOMAIN"
    echo "CLOUDFLARE_API_TOKEN=$CLOUDFLARE_API_TOKEN"
  fi
  if [[ ",$profiles," == *",manga,"* ]]; then
    echo ""
    echo "# Manga (manga profile)"
    echo "MANGA_DIR=$MANGA_DIR"
    echo "SUWAYOMI_USER=$SUWAYOMI_USER"
    echo "SUWAYOMI_PASSWORD=$SUWAYOMI_PASSWORD"
  fi
  if [[ ",$profiles," == *",samba,"* ]]; then
    echo ""
    echo "# Samba (samba profile)"
    echo "SAMBA_USER=$SAMBA_USER"
    echo "SAMBA_PASSWORD=$SAMBA_PASSWORD"
  fi
  if [[ ",$profiles," == *",tailscale,"* ]]; then
    echo ""
    echo "# Tailscale (tailscale profile)"
    echo "TS_AUTHKEY=${TS_AUTHKEY:-}"
    echo "TS_HOSTNAME=${TS_HOSTNAME:-couchpilot}"
  fi
  if [[ -n "${BACKUP_DIR:-}" || -n "${BACKUP_PASSPHRASE:-}" ]]; then
    echo ""
    echo "# Backups (scripts/backup.sh)"
    [[ -n "${BACKUP_DIR:-}" ]] && echo "BACKUP_DIR=$BACKUP_DIR"
    [[ -n "${BACKUP_PASSPHRASE:-}" ]] && echo "BACKUP_PASSPHRASE=$BACKUP_PASSPHRASE"
  fi
} > .env
chmod 600 .env
manifest_add "wrote-env .env"

# ── Generate derived files ────────────────────────────────────────────────────

# Hardware transcoding override
rm -f compose.hwaccel.yml
if [[ "$HWACCEL" == "vaapi" ]]; then
  sed "s/__RENDER_GID__/$RENDER_GID/g" templates/hwaccel-vaapi.yml.tmpl > compose.hwaccel.yml
  manifest_add "generated-file compose.hwaccel.yml"
elif [[ "$HWACCEL" == "nvidia" ]]; then
  cp templates/hwaccel-nvidia.yml.tmpl compose.hwaccel.yml
  manifest_add "generated-file compose.hwaccel.yml"
fi

# Extra drives override
rm -f compose.drives.yml
if [[ -n "$EXTRA_DRIVES" ]]; then
  {
    echo "# Generated by ./mc setup — extra media drives. Re-run setup to change."
    echo "services:"
    for svc in jellyfin sonarr radarr bazarr qbittorrent; do
      echo "  $svc:"
      echo "    volumes:"
      n=2
      for d in $EXTRA_DRIVES; do
        if [[ "$svc" == "jellyfin" ]]; then
          echo "      - $d:/data$n:ro"
        else
          echo "      - $d:/data$n"
        fi
        n=$((n+1))
      done
    done
    echo "  samba:"
    echo "    volumes:"
    n=2
    for d in $EXTRA_DRIVES; do
      echo "      - type: bind"
      echo "        source: $d"
      echo "        target: /storage/data$n"
      echo "        bind:"
      echo "          propagation: rslave"
      n=$((n+1))
    done
  } > compose.drives.yml
  manifest_add "generated-file compose.drives.yml"
fi

# Domain vhosts
rm -f caddy/sites/domain.caddy
if [[ -n "${DOMAIN:-}" ]]; then
  sed "s/__DOMAIN__/$DOMAIN/g" templates/domain.caddy.tmpl > caddy/sites/domain.caddy
  manifest_add "generated-file caddy/sites/domain.caddy"
fi

# Pi-hole split-horizon hosts (only when both dns profile AND domain are on)
rm -f pihole/etc-pihole/hosts/local-dns.list 2>/dev/null || true
if [[ ",$profiles," == *",dns,"* && -n "${DOMAIN:-}" ]]; then
  mkdir_logged "pihole/etc-pihole/hosts"
  sed -e "s/__LAN_IP__/$LAN_IP/g" -e "s/__DOMAIN__/$DOMAIN/g" \
    templates/pihole-hosts.tmpl > pihole/etc-pihole/hosts/local-dns.list
  manifest_add "generated-file pihole/etc-pihole/hosts/local-dns.list"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
title "Setup complete!"
say "Start everything with:   ${BOLD}./mc up${NC}"
say "See your URLs with:      ${BOLD}./mc ip${NC}"
if [[ "$HWACCEL" != "none" ]]; then
  say ""
  say "One manual step for GPU transcoding — in Jellyfin, after first login:"
  say "  Dashboard → Playback → Transcoding → Hardware acceleration:"
  case "$HWACCEL" in
    vaapi)  say "    pick 'Intel QuickSync (QSV)' (Intel) or 'VA-API' (AMD)" ;;
    nvidia) say "    pick 'NVIDIA NVENC'" ;;
  esac
fi
if [[ -n "${DOMAIN:-}" ]]; then
  say ""
  say "Domain checklist (details in docs/domain-https.md):"
  say "  • Cloudflare DNS: add A records for each service name → your server's"
  say "    IP (LAN IP for home-only, Tailscale IP for remote — 'DNS only', grey cloud)"
fi
