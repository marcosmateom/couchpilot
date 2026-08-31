# Custom domain + HTTPS

Everything in couchpilot works without a domain at `http://server-ip:port`.
A domain gets you `https://jellyfin.yourdomain.com` style URLs with real
certificates — nicer, and required if you ever want password-protected
public access. Cost: a domain is ~$10/year; everything else here is free.

## What you need

1. **A domain** — any registrar works (Cloudflare, Namecheap, Porkbun...).
2. **The domain on Cloudflare (free plan)** — couchpilot gets its certificates
   through Cloudflare's DNS API. If you bought the domain elsewhere, add it to
   Cloudflare (dashboard → Add a site) and point your registrar's nameservers
   at the two nameservers Cloudflare gives you.
3. **A Cloudflare API token**:
   - Cloudflare dashboard → My Profile → **API Tokens** → Create Token
   - Use the **"Edit zone DNS"** template
   - Zone Resources: *Include → Specific zone → yourdomain.com*
   - Create it and copy the token (you can't see it again later)

## Setup

Re-run `./mc setup`, answer **y** to the domain question, paste the domain
and token. The wizard generates `caddy/sites/domain.caddy` (one HTTPS vhost
per service). Then `./mc up` — Caddy requests certificates automatically
via DNS-01, which means **no ports need to be opened on your router**.

Watch it work (or fail) with `./mc logs caddy`. Success is silent; errors
mention "obtaining certificate". A malformed token stops Caddy from starting
at all — the log will say the token "appears invalid".

## Making the names resolve

Certificates are automatic, but *DNS records are up to you* — you decide
where each name points:

| You want | Point the A records at | Where |
|---|---|---|
| Home use only | Your server's LAN IP (e.g. 192.168.1.50) | Cloudflare DNS, **or** enable the `dns` profile and Pi-hole answers them locally for free |
| Remote via Tailscale | Your Tailscale IP (`./mc ip` shows it) | Cloudflare DNS |

Add one **A record** per service name (`jellyfin`, `sonarr`, `radarr`,
`bazarr`, `prowlarr`, `qbit`, `jellyseerr`, `requests`, plus `jackett`,
`rdt`, `manga`, `reader`, `pihole` if you use those profiles).

> **Important:** set each record to **DNS only** (grey cloud, not orange).
> The Cloudflare proxy can't reach LAN or Tailscale IPs — and private IPs
> in public DNS are harmless (they only mean something on *your* network).

If you enabled the `dns` profile *and* a domain, the wizard also generated
Pi-hole's split-horizon file — devices at home using Pi-hole resolve
`*.yourdomain.com` straight to the server's LAN IP, no Cloudflare records
needed for home use.

## qBittorrent note

qBittorrent validates the `Host` header. Domain mode pins it to
`qbit.yourdomain.com`; if you've changed qBittorrent's
*WebUI → Server domains* setting from its default `*`, add
`qbit.yourdomain.com` to it.

## Advanced: exposing Jellyfin publicly (Cloudflare Tunnel)

If you want family to stream **without** Tailscale, a Cloudflare Tunnel can
publish Jellyfin (only) to the internet — no open ports. This is deliberately
not part of the default stack: exposing services publicly is a real security
decision. Sketch:

1. Cloudflare Zero Trust → Networks → Tunnels → create a tunnel, copy the token.
2. Add to `docker-compose.yml`:
   ```yaml
   cloudflared:
     image: cloudflare/cloudflared:latest
     restart: unless-stopped
     command: tunnel --no-autoupdate run --token YOUR_TUNNEL_TOKEN
     networks: [media_net]
   ```
3. In the tunnel's Public Hostname tab: `watch.yourdomain.com` →
   `http://jellyfin:8096`.

Only do this for Jellyfin (it has real authentication). Never tunnel the
*arr apps or download clients.
