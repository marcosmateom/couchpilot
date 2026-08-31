# Remote access with Tailscale

Tailscale is a free (up to 100 devices) personal VPN. Every device you
install it on joins your private "tailnet" and can reach the others —
no port forwarding, no public exposure, works behind CGNAT.

With the `tailscale` profile enabled, your media server joins the tailnet
from inside Docker. Because the container uses host networking, the
machine's Tailscale IP behaves exactly like its LAN IP: **every service
URL from `./mc ip` works remotely, same ports**, e.g.
`http://100.x.y.z:8096` for Jellyfin from anywhere.

## Setup

1. Create a free account at <https://tailscale.com> and install the app on
   your phone/laptop.
2. Enable the profile: `./mc setup` → answer **y** to Tailscale.
   - With an **auth key** (admin console → Settings → Keys → *Generate
     auth key*): the server logs in by itself.
   - Without one: run `./mc logs tailscale` and open the login URL it prints.
3. `./mc up`, then check the machine appears in your
   [admin console](https://login.tailscale.com/admin/machines).

The login persists in `./tailscale/state` — the auth key is only needed once.

Tip: in the admin console, disable key expiry for the server
(machine → ⋯ → Disable key expiry) so it doesn't log itself out in 90 days.

## Nice extras

- **MagicDNS** (admin console → DNS): reach the server by name —
  `http://couchpilot:8096` — instead of the 100.x IP.
- **Serving your whole LAN** (optional): Tailscale can advertise your home
  subnet so remote devices reach *everything* at home. That's a host-level
  decision; see Tailscale's [subnet router docs](https://tailscale.com/kb/1019/subnets).
- **Domain mode**: if you also set up a domain (docs/domain-https.md), point
  the Cloudflare A records at the Tailscale IP and remote devices get the
  same pretty HTTPS URLs.

## Already run Tailscale on the host?

Skip the profile — the wizard detects a running `tailscaled` and skips it
automatically. A host install already gives you everything above; running
both would fight over the network.
