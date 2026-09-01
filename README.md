# couchpilot 🛋️

**Your own Netflix, on a computer at home, in three commands.**

couchpilot is a complete self-hosted media center: it finds the movies and
shows you ask for, downloads them, fetches subtitles, organizes everything,
and streams it to your TV, phone, or browser — with a pretty request page
your family can use without ever asking you anything.

```bash
git clone https://github.com/marcosmateom/couchpilot.git
cd couchpilot
./mc setup     # asks a few questions, sets everything up
./mc up        # starts everything
```

Then wire the apps together once — 15 minutes, see
[First-time app setup](#first-time-app-setup-15-minutes-once) below — and
request your first movie. 🎬

---

## What's in the box

| App | What it does | Port |
|---|---|---|
| **Jellyfin** | Streams your library — the "Netflix" part | 8096 |
| **Jellyseerr** | Pretty request page ("I want to watch X") | 5055 |
| **Radarr** | Finds and manages movies | 7878 |
| **Sonarr** | Finds and manages TV shows | 8989 |
| **Bazarr** | Downloads subtitles automatically | 6767 |
| **Prowlarr** | Manages your indexers (where to search) | 9696 |
| **qBittorrent** | Downloads the actual files | 8080 |
| **FlareSolverr** | Helper that unblocks protected indexers | — |
| **Caddy** | The front door — routes every URL above | — |

**Optional extras** (the setup wizard asks; all off by default):

| Extra | What it adds |
|---|---|
| **Pi-hole + Unbound** | Network-wide ad blocking for every device at home |
| **Tailscale** | Use everything remotely, from anywhere, for free — no router config |
| **Suwayomi + Komga** | The same idea, but for manga: auto-download + reader |
| **Samba** | Your media folder as a Windows network drive |
| **Jackett / RDTClient** | Extra indexer proxy / Real-Debrid downloads |

Everything runs in Docker. Nothing is installed on your system except
Docker itself.

## What you need

- **A Linux machine** that stays on: an old PC, a mini-PC, a NAS that runs
  Docker, a Raspberry Pi 4/5. 4 GB RAM is plenty to start.
  > **Windows/macOS**: not supported. Run a Linux VM if you must (WSL2 at
  > your own risk — Docker Desktop's networking, GPU passthrough and DNS
  > handling all behave differently there).
- **Docker** — if it's missing, `./mc setup` offers to install it for you.
  (Manual: `curl -fsSL https://get.docker.com | sh`)
- **Disk space** for your media, obviously.

## The three access levels

You choose during setup; you can change your mind anytime by re-running it.

1. **Just home (default)** — everything at `http://server-ip:port` on your
   WiFi. Zero accounts, zero config, works immediately.
2. **+ Tailscale** — same URLs work from anywhere in the world, through a
   free personal VPN. No ports opened, nothing exposed to the internet.
   → [docs/tailscale.md](docs/tailscale.md)
3. **+ Your own domain** — `https://jellyfin.yourdomain.com` with real
   certificates (needs a ~$10/yr domain on Cloudflare's free plan).
   → [docs/domain-https.md](docs/domain-https.md)

## First-time app setup (15 minutes, once)

If you haven't yet: run `./mc setup` (answer the questions), **then**
`./mc up` (the start button). The apps below are only reachable after both —
`./mc ip` prints every URL.

> **Know your way around?** You can skip the wizard: `cp .env.example .env`,
> edit it (it documents every variable, including the no-wizard notes at the
> top), then `./mc up`.

Now wire the apps together, in this order. Each step here is the short
version — **[docs/first-time-setup.md](docs/first-time-setup.md) walks
through the same steps click by click**, with explanations of what each app
is and why the order matters. New to the *arr world? Read that instead.

1. **qBittorrent** (`:8080`) — get the temporary password from
   `./mc logs qbittorrent` (look for "temporary password"), log in as
   `admin`, then Settings → WebUI → change username/password.
   Settings → Downloads → Default Save Path: `/data/downloads/complete`,
   and tick "Keep incomplete torrents in": `/data/downloads/incomplete`.
   [→ guide](docs/first-time-setup.md#qbittorrent-the-downloader)
2. **Sonarr** (`:8989`) — create your login (first visit asks). Settings →
   Media Management → Add Root Folder: `/data/tv`. Settings → Download
   Clients → add qBittorrent: host `172.28.0.50`, port `8080`, your
   qBittorrent login.
   [→ guide](docs/first-time-setup.md#sonarr-tv-shows)
3. **Radarr** (`:7878`) — same, with root folder `/data/movies` and the same
   qBittorrent client.
   [→ guide](docs/first-time-setup.md#radarr-movies)
4. **Prowlarr** (`:9696`) — create your login. Add indexers (Indexers → Add;
   start with a few public ones). Then Settings → Apps → add **Sonarr**
   (server `http://sonarr:8989`, its API key is in Sonarr → Settings →
   General) and **Radarr** (`http://radarr:7878`) — Prowlarr pushes every
   indexer to both automatically. Now you can add your first show/movie in
   Sonarr/Radarr.
   [→ guide (read this one!)](docs/first-time-setup.md#prowlarr-the-search-brain)
5. **Bazarr** (`:6767`) — Settings → Sonarr: address `sonarr`, port `8989`,
   API key from Sonarr. Settings → Radarr: address `radarr`, port `7878`.
   Settings → Languages: pick yours. Add a couple of providers
   (OpenSubtitles etc.).
   [→ guide](docs/first-time-setup.md#bazarr-subtitles)
6. **Jellyfin** (`:8096`) — the wizard creates your account. Add libraries:
   Movies → `/data/movies`, Shows → `/data/tv`. If setup enabled GPU
   transcoding: Dashboard → Playback → Transcoding → pick your encoder
   ([which one?](docs/hardware-transcoding.md)).
   [→ guide](docs/first-time-setup.md#jellyfin-the-streaming-part)
7. **Jellyseerr** (`:5055`) — Sign in with your **Jellyfin** account, URL
   `http://jellyfin:8096`. Add Radarr (`radarr`, port `7878`, root
   `/data/movies`) and Sonarr (`sonarr`, port `8989`, root `/data/tv`),
   API keys from each app. Mark both as default.
   [→ guide](docs/first-time-setup.md#jellyseerr-the-request-page)

Done. From now on: request in Jellyseerr → appears in Jellyfin.
Family members: make them Jellyfin users; they log into Jellyseerr with that.

**You don't have to go through Jellyseerr yourself** — adding things
directly in Sonarr (Series → Add New) or Radarr (Movies → Add New) does the
same job with more control (pick the exact release, monitor specific
seasons, upgrade qualities). Think of Sonarr/Radarr as the control room and
Jellyseerr as the reception desk for everyone else.
[→ more](docs/first-time-setup.md#do-i-even-need-jellyseerr)

## Daily driving

```bash
./mc ip        # every service URL
./mc status    # what's running
./mc logs sonarr
./mc update    # update all apps (run every few weeks)
./mc setup     # change any decision — it remembers your answers
./mc down      # stop everything (nothing is lost)
./mc uninstall # guided removal — your media is never touched
```

Backups of all settings (encrypted, one file): see
[docs/backup-restore.md](docs/backup-restore.md). Media on its own drive or
several drives: [docs/storage.md](docs/storage.md).

## Troubleshooting (the top 5)

| Symptom | Fix |
|---|---|
| A page shows **502** | That app is off (optional profile not enabled) or still starting — `./mc status` |
| Libraries suddenly **empty** | A drive isn't mounted — `df -h`, then see [docs/storage.md](docs/storage.md) |
| Downloads never **import** | qBittorrent's save path must be exactly `/data/downloads/complete` (step 1 above) |
| **Permission denied** in logs | Media folder not owned by your user: `sudo chown -R $(id -u):$(id -g) ~/media` |
| Changed `.env` by hand, nothing happened | Restart doesn't reload config — run `./mc up` |

Something else: `./mc logs <app>` almost always names the problem.

## How it's wired (for the curious)

```
                    you / your family
                          │
              http://server-ip:port   (or https://app.yourdomain.com)
                          │
                       [Caddy]  ← the only door; every web UI sits behind it
                          │
   Jellyfin ── Jellyseerr ── Sonarr/Radarr ── Prowlarr ── qBittorrent
       │              (request)    (manage)     (search)     (download)
       └── streams /data (read-only) ──────────────┴── writes /data
```

- One shared `/data` folder means imports are instant **hardlinks**, not
  copies ([why](docs/storage.md)).
- Every container: unprivileged, runs as your user, pinned DNS,
  `no-new-privileges`, config in `./<app>/config` next to the compose file.
- Optional parts are [Compose profiles](https://docs.docker.com/compose/how-tos/profiles/) —
  a disabled extra simply doesn't exist.
- `./mc` is a thin wrapper around `docker compose` that makes `.env` always
  win over your shell environment (a classic Compose footgun).

## License

MIT — do whatever you want with it.
