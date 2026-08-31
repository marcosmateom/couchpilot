# Hardware transcoding

When a device can't play a file natively (wrong codec, limited bandwidth),
Jellyfin converts it on the fly — *transcoding*. On CPU this is heavy; a GPU
does it almost for free. Any Intel CPU with integrated graphics from the
last decade handles multiple 4K streams.

## No GPU, or a weak machine (Raspberry Pi)?

CPU transcoding *works*, but on a small CPU — a Raspberry Pi especially —
it's so slow it isn't practical: video stutters, buffers, or plays in slow
motion while the CPU sits at 100%. Don't fight it; avoid transcoding
instead:

- **Direct play** is when the device plays the file as-is — zero transcoding,
  zero CPU. It happens automatically whenever the format is compatible.
- Most modern TVs/phones direct-play **H.264 (x264) video in MP4/MKV**
  without trouble, so prefer grabbing releases in that format — in
  Sonarr/Radarr this mostly means preferring 1080p x264 releases over
  x265/HEVC ones.
- If a file won't play on one device, it's usually cheaper to grab a
  compatible version of it than to transcode the incompatible one forever.

`./mc setup` detects your GPU and wires it up (it generates
`compose.hwaccel.yml` — never edit `docker-compose.yml` for this). What it
looks for:

| Vendor | Detected via | Jellyfin encoder |
|---|---|---|
| Intel (QuickSync) | `/dev/dri/renderD*` with Intel vendor ID | **QSV** |
| AMD | `/dev/dri/renderD*` with AMD vendor ID | **VA-API** |
| NVIDIA | `nvidia-smi` + Docker's NVIDIA runtime | **NVENC** |

## The one manual step

Docker can only hand the GPU to the container — Jellyfin still needs to be
told to use it (once):

**Jellyfin → Dashboard → Playback → Transcoding → Hardware acceleration** →
pick your encoder from the table above → Save.

Test: play something and force a lower quality; `docker stats jellyfin`
should show modest CPU while it plays.

## NVIDIA: extra install

NVIDIA needs its container toolkit before Docker can see the GPU. Open a
terminal on the server and run the commands below **one at a time** — paste
a line, press Enter, wait for it to finish, then paste the next (the ones
ending in `\` are a single command split across lines; copy those whole):

```bash
# Debian/Ubuntu — full guide: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -sL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

Then re-run `./mc setup` — it will now offer NVENC.

## Troubleshooting

- **"Playback failed" only when transcoding**: wrong encoder selected in
  Jellyfin, or the GPU isn't reaching the container. `docker exec jellyfin
  ls /dev/dri` should list `renderD128`.
- **Permission denied on /dev/dri**: your render group ID changed (distro
  update). Re-run `./mc setup` — it re-detects the GID.
- **No /dev/dri at all**: no GPU kernel driver. On Intel this usually means
  a very old kernel or graphics disabled in BIOS.
