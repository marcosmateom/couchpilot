# ── Stage 1: compile Caddy with the Cloudflare DNS plugin ────────────────────
# xcaddy builds a custom binary that supports ACME DNS-01 challenges via
# Cloudflare, so Caddy can obtain Let's Encrypt certs without port-80
# exposure. The plugin is dormant unless you enable domain mode in ./mc setup.
FROM caddy:builder AS builder

RUN xcaddy build \
    --with github.com/caddy-dns/cloudflare

# ── Stage 2: minimal runtime image ───────────────────────────────────────────
FROM caddy:latest

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
