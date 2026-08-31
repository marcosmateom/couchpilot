#!/usr/bin/env bash
# mc — couchpilot management helper
# Usage:  ./mc <command>
#
#   setup      Interactive first-time setup (safe to re-run any time)
#   up         Pull images + start all services
#   down       Stop all services (data is preserved)
#   restart    Restart one or all services:   ./mc restart sonarr
#   logs       Follow logs for a service:     ./mc logs caddy
#   pull       Pull latest images (no restart)
#   status     Show container status + ports
#   update     Pull latest images + restart changed containers
#   dns        Test Pi-hole DNS resolution (dns profile)
#   ip         Show every service URL
#   uninstall  Remove what couchpilot created (guided, with warnings)

set -euo pipefail
cd "$(dirname "$0")"

# Load .env with shell-export precedence flipped: sourcing it here means the
# values in .env always win over variables exported in your shell profile
# (raw `docker compose` would let the shell win — a classic footgun).
set -a; source .env 2>/dev/null || true; set +a

# ── Colour helpers ─────────────────────────────────────────────────────────────
BOLD='\033[1m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
header() { echo -e "\n${BOLD}${CYAN}── $* ──${NC}"; }

# Service → port table (single source of truth for `ip`)
SERVICES=(
  "Jellyfin:8096"
  "Jellyseerr:5055"
  "Sonarr:8989"
  "Radarr:7878"
  "Bazarr:6767"
  "Prowlarr:9696"
  "qBittorrent:8080"
  "Jackett:9117:jackett"
  "RDTClient:6500:rdtclient"
  "Suwayomi:4567:manga"
  "Komga:25600:manga"
  "Pi-hole:8081:dns"
)

need_env() {
  if [[ ! -f .env ]]; then
    echo -e "${YELLOW}No .env found — run  ./mc setup  first.${NC}"
    exit 1
  fi
}

# ── Commands ───────────────────────────────────────────────────────────────────
case "${1:-help}" in

  setup)
    exec bash scripts/setup.sh
    ;;

  up)
    need_env
    header "Starting couchpilot"
    docker compose pull --quiet
    docker compose up -d --remove-orphans
    echo ""
    echo -e "${GREEN}All services up.${NC}"
    "$0" ip
    ;;

  down)
    header "Stopping couchpilot"
    docker compose down
    ;;

  restart)
    header "Restarting ${2:-all services}"
    if [[ -n "${2:-}" ]]; then
        docker compose restart "$2"
    else
        docker compose restart
    fi
    ;;

  logs)
    service="${2:-}"
    [[ -z "$service" ]] && { echo "Usage: $0 logs <service>"; exit 1; }
    docker compose logs -f --tail=100 "$service"
    ;;

  pull)
    header "Pulling latest images"
    docker compose pull
    ;;

  status)
    header "Service status"
    docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
    ;;

  update)
    need_env
    header "Updating all services"
    docker compose pull --quiet
    docker compose up -d --remove-orphans
    docker image prune -f --filter "dangling=true" &>/dev/null || true
    echo -e "${GREEN}Update complete.${NC}"
    ;;

  dns)
    header "DNS test"
    if [[ ",${COMPOSE_PROFILES:-}," != *",dns,"* ]]; then
        echo "The dns profile (Pi-hole + Unbound) is not enabled."
        echo "Enable it via  ./mc setup  or add 'dns' to COMPOSE_PROFILES in .env."
        exit 0
    fi
    target="${LAN_IP:-127.0.0.1}"
    echo "Querying Pi-hole at ${target}:53 ..."
    if command -v dig &>/dev/null; then
        dig @"$target" google.com +short | head -3
        [[ -n "${DOMAIN:-}" ]] && dig @"$target" "jellyfin.$DOMAIN" +short
    elif command -v nslookup &>/dev/null; then
        nslookup google.com "$target"
    else
        echo "Install dnsutils for DNS testing:  sudo apt install dnsutils"
    fi
    ;;

  ip)
    server_ip="${LAN_IP:-$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || hostname -I 2>/dev/null | awk '{print $1}')}"
    server_ip="${server_ip:-<server-ip>}"
    header "Service URLs"
    for entry in "${SERVICES[@]}"; do
        IFS=':' read -r name port profile <<< "$entry"
        # Skip services whose profile isn't enabled
        if [[ -n "${profile:-}" && ",${COMPOSE_PROFILES:-}," != *",${profile},"* ]]; then
            continue
        fi
        if [[ -n "${DOMAIN:-}" ]]; then
            sub="$(echo "$name" | tr '[:upper:]' '[:lower:]')"
            case "$sub" in
                qbittorrent) sub="qbit" ;;
                rdtclient)   sub="rdt" ;;
                suwayomi)    sub="manga" ;;
                komga)       sub="reader" ;;
                pi-hole)     sub="pihole" ;;
            esac
            printf "  %-14s http://%s:%s   https://%s.%s\n" "$name" "$server_ip" "$port" "$sub" "$DOMAIN"
        else
            printf "  %-14s http://%s:%s\n" "$name" "$server_ip" "$port"
        fi
    done
    echo ""
    echo "  Server IP: $server_ip"
    if [[ ",${COMPOSE_PROFILES:-}," == *",tailscale,"* ]]; then
        ts_ip="$(docker exec tailscale tailscale ip -4 2>/dev/null || echo 'n/a (is it up?)')"
        echo "  Tailscale: $ts_ip  — same ports work remotely"
    fi
    if [[ ",${COMPOSE_PROFILES:-}," == *",dns,"* ]]; then
        echo "  Ad blocking: point your router's DNS at $server_ip"
    fi
    ;;

  uninstall)
    exec bash scripts/uninstall.sh
    ;;

  help|*)
    echo ""
    echo -e "${BOLD}mc — couchpilot CLI${NC}"
    echo ""
    echo "  setup           First-time setup wizard (safe to re-run)"
    echo "  up              Pull images + start all services"
    echo "  down            Stop all services"
    echo "  restart [svc]   Restart one or all services"
    echo "  logs <svc>      Tail logs for a service"
    echo "  pull            Pull latest images (no restart)"
    echo "  status          Show container status + ports"
    echo "  update          Pull + restart changed containers"
    echo "  dns             Test Pi-hole DNS resolution"
    echo "  ip              Show all service URLs"
    echo "  uninstall       Guided removal (with warnings)"
    echo ""
    ;;
esac
