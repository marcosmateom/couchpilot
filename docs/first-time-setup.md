# First-time setup, explained for humans

This is the long version of the README's checklist — what each app actually
is, why the steps are in this order, and every click spelled out. Nothing
here is hard; there are just several apps that need to be introduced to each
other once.

Before any of this: run `./mc setup`, then `./mc up`, and keep the output of
`./mc ip` handy — it lists every URL used below.

## How the pieces fit together

Think of it as a little factory:

```
 you ask for a movie          (Jellyseerr — or Radarr/Sonarr directly)
        ↓
 something searches for it   (Sonarr for shows, Radarr for movies)
        ↓
 ...using your indexers      (Prowlarr manages the list of places to search)
        ↓
 something downloads it      (qBittorrent)
        ↓
 it gets moved & renamed     (Sonarr/Radarr again — automatic)
        ↓
 subtitles get fetched       (Bazarr — automatic)
        ↓
 you press play              (Jellyfin)
```

Once wired up, the only part you ever touch again is the first and last line.

A term you'll see constantly — **API key**: a password that apps use to talk
to *each other* (instead of your login). Every *arr app shows its own under
**Settings → General → API Key**. When app A wants to talk to app B, you
paste **B's** key into A.

---

## qBittorrent: the downloader

Open `http://server-ip:8080`.

1. **Log in.** Username is `admin`; the first password is random — find it
   with `./mc logs qbittorrent` (look for a line mentioning "temporary
   password").
2. **Change it**: Settings (the gear) → **WebUI** → set your own username and
   password → Save. (The temporary one changes on every restart, so don't
   skip this.)
3. Settings → **Downloads**:
   - **Default Save Path**: `/data/downloads/complete`
   - Tick **Keep incomplete torrents in** and set it to
     `/data/downloads/incomplete`
   - Save.

That path matters more than it looks: it's on the same disk mount the other
apps see, which is what makes imports instant (hardlinks) instead of copies.

Optional but good: forward port **6881** (TCP+UDP) to this machine on your
router — not required to download, but speeds things up and helps seeding.

---

## Prowlarr: the search brain

Open `http://server-ip:9696`. This is the app newcomers find weirdest, so
here's the missing context first.

**What's an indexer?** Torrents live on tracker sites, and each site has its
own search. An *indexer* is simply one of those sites, plugged in so your
apps can search it automatically. Without at least one indexer, Sonarr and
Radarr have nowhere to search.

**Why Prowlarr?** You *could* add indexers to Sonarr and Radarr separately —
old guides do exactly that. Prowlarr exists so you add each indexer **once**
and it pushes them to both apps (and keeps them synced) forever. You'll
thank yourself later.

Setup:

1. First visit asks you to create a login — do it.
2. **Add indexers**: **Indexers → Add Indexer**. Search the list, click one,
   then **Test** and **Save**.
   - Start with well-known public ones (search for them in the list):
     `1337x`, `TheRARBG`, `EZTV` (TV), `YTS` (movies, small files). Add 3–5;
     more sources = more results.
   - **Private trackers** (invite-only sites) work too and are usually
     higher quality — pick yours from the list and paste the API key *from
     that site's profile page*.
3. **Cloudflare-protected indexers**: some sites hide behind a
   "checking your browser" page, and the Test button fails with a Cloudflare
   error. That's what FlareSolverr (already running) is for:
   - Settings → **Indexers** → **Add** (under Indexer Proxies) →
     **FlareSolverr**, Host: `http://flaresolverr:8191`, Tags: `cf` → Save.
   - On the failing indexer, add the tag `cf` — it now goes through the
     unblocking proxy.
4. **Connect it to Sonarr and Radarr**: Settings → **Apps** → **+**:
   - **Sonarr**: Prowlarr Server `http://prowlarr:9696`, Sonarr Server
     `http://sonarr:8989`, API Key: *from Sonarr* (Settings → General) →
     Test → Save.
   - **Radarr**: same idea — `http://radarr:7878`, API key from Radarr.

That's it. Open Sonarr or Radarr → Settings → Indexers and you'll see every
indexer already there, tagged "Prowlarr". Never add indexers anywhere else
again — always in Prowlarr.

---

## Sonarr: TV shows

Open `http://server-ip:8989`.

1. **Root folder** (where your shows live): Settings → **Media Management**
   → **Add Root Folder** → `/data/tv`.
2. **Download client** (how it hands work to qBittorrent): Settings →
   **Download Clients** → **+** → qBittorrent:
   - Host: `172.28.0.50`  ← the IP, not a name (qBittorrent rejects
     container names — this is expected)
   - Port: `8080`
   - Username/password: your qBittorrent login from earlier
   - Test → Save.
3. Indexers came from Prowlarr already — nothing to do.
4. **Add your first show**: Series → **Add New** → search → pick the show:
   - Root Folder: `/data/tv`
   - Quality Profile: `HD-1080p` is a sane default (profiles decide what
     quality to grab; you can tune them later under Settings → Profiles)
   - **Add**. Sonarr searches, sends the download to qBittorrent, waits,
     imports, renames. Watch it happen under **Activity → Queue**.

Sonarr keeps monitoring: when the next episode airs, it grabs it by itself.

---

## Radarr: movies

Open `http://server-ip:7878`. It's Sonarr's twin, so this will feel familiar:

1. Settings → **Media Management** → **Add Root Folder** → `/data/movies`.
2. Settings → **Download Clients** → **+** → qBittorrent → host `172.28.0.50`,
   port `8080`, your login → Test → Save.
3. **Add a movie**: Movies → **Add New** → search → Root Folder
   `/data/movies`, Quality Profile `HD-1080p` → Add.

---

## Bazarr: subtitles

Open `http://server-ip:6767`. Bazarr watches what Sonarr/Radarr import and
fetches subtitles for it.

1. Settings → **Sonarr**: Address `sonarr`, Port `8989`, API key *from
   Sonarr* → Test → Save.
2. Settings → **Radarr**: Address `radarr`, Port `7878`, API key *from
   Radarr* → Test → Save.
3. Settings → **Languages**: create a Language Profile with the languages
   you want, and set it as default for series and movies.
4. Settings → **Providers**: add a few subtitle sources. `OpenSubtitles.com`
   (free account required) plus one or two no-account ones like `Podnapisi`
   is a fine start.

Subtitles then appear next to each video file a few minutes after import —
Jellyfin picks them up automatically.

---

## Jellyfin: the streaming part

Open `http://server-ip:8096`.

1. The first-run wizard creates your account.
2. **Add libraries**:
   - Content type **Movies** → folder `/data/movies`
   - Content type **Shows** → folder `/data/tv`
   - Leave metadata settings at their defaults — they're good.
3. If `./mc setup` enabled GPU transcoding, one manual step: **Dashboard →
   Playback → Transcoding → Hardware acceleration** → pick your encoder
   ([which one is mine?](hardware-transcoding.md)).
4. Install the Jellyfin app on your TV/phone/tablet, point it at
   `http://server-ip:8096`, done.

**Family accounts**: Dashboard → Users → **+**. Each person gets their own
watch history, and these same accounts log into Jellyseerr.

---

## Jellyseerr: the request page

Open `http://server-ip:5055`. This is the page you actually give people.

1. **Sign in with Jellyfin** → server URL `http://jellyfin:8096` → your
   Jellyfin login. (It imports Jellyfin users automatically — that's why
   Jellyfin came first.)
2. Add **Radarr**: Settings → Services → **Add Radarr Server** →
   Hostname `radarr`, Port `7878`, API key from Radarr, Quality Profile
   `HD-1080p`, Root Folder `/data/movies`, tick **Default Server** → Save.
3. Add **Sonarr**: same — `sonarr`, `8989`, API key from Sonarr, root
   `/data/tv`, Default Server → Save.

Now anyone with a Jellyfin account opens Jellyseerr, hits **Request** on a
poster, and a few minutes later it's in Jellyfin. No more "can you download
X for me".

---

## Do I even need Jellyseerr?

No — it's the friendly front door for *other people*. You can drive the
machinery directly, and many people prefer it:

- **Movies**: Radarr → **Add New** — searches, grabs, imports.
- **Shows**: Sonarr → **Add New** — same, plus it keeps following the show
  for future episodes.
- Sonarr/Radarr give you more control than Jellyseerr: pick the exact
  release (**interactive search**: the person icon next to a
  series/movie), monitor only certain seasons, upgrade qualities, etc.

A good mental model: **Sonarr/Radarr are the control room, Jellyseerr is
the reception desk.** Use the control room yourself; give guests the desk.

---

## Something didn't work?

- Anything with a **Test** button: use it — the error text is usually the
  actual problem (wrong API key, wrong port).
- Downloads sit at 100% but never import → the qBittorrent save path isn't
  exactly `/data/downloads/complete` ([why it matters](storage.md)).
- An indexer fails with a Cloudflare error → FlareSolverr step in
  [Prowlarr](#prowlarr-the-search-brain) above.
- Everything else: `./mc logs <app>` nearly always names the culprit.
