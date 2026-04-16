# Tailscale Monitor - Plasma 6 Applet

A KDE Plasma 6 panel applet for monitoring Tailscale VPN status with service-aware peer management.

Built for a Raspberry Pi 5 (CM5 in Argon One laptop case) running Raspberry Pi OS Bookworm with KDE Plasma on Wayland. Should work on other Plasma 6 setups but has only been tested on this hardware.

## Features

- **Panel icon** — Tailscale logo that switches between connected (active dots) and disconnected (faded) states
- **Device info** — hostname, Tailscale IP, DNS name, relay server, HTTPS URL (clickable to copy)
- **Network info** — tailnet name, exit node, version
- **Peer list** — all peers sorted online-first, with status indicators
- **Service probing** — detects available services on online peers (SSH, VNC, RDP, NoMachine, HTTP, HTTPS)
- **One-click launch** — buttons appear per-peer based on detected services:
  - **SSH** via Konsole
  - **VNC** via RealVNC Viewer (auto-detected) or Remmina
  - **RDP** via Remmina
  - **NoMachine** via nxplayer (generates session file)
  - **HTTP** via default browser
  - **HTTPS** copy to clipboard
- **Click to copy** — click any peer name or DNS name row to copy the full domain to clipboard

## Prerequisites

Install and configure [Tailscale](https://tailscale.com/download) first:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

## Dependencies

- KDE Plasma 6
- Tailscale (`tailscale` CLI)
- Python 3
- `wl-copy` (wl-clipboard) for clipboard support on Wayland

Optional, depending on which services your peers run:

- Konsole (SSH)
- Remmina + remmina-plugin-rdp + remmina-plugin-vnc (RDP/VNC)
- RealVNC Viewer (VNC to RealVNC servers)
- NoMachine client (NoMachine)

## Install

```bash
bash install.sh
```

Then right-click the panel, **Add Widgets**, search for **Tailscale Monitor**, and drag it to the panel.

If the widget doesn't appear, restart Plasma:

```bash
kquitapp6 plasmashell && kstart plasmashell
```

## How it works

A Python helper (`tailscale-status.py`) runs every 5 seconds via Plasma's DataSource engine. It calls `tailscale status --json` and probes open ports on online peers (TCP connect with 300ms timeout). The QML UI renders the results.

VNC server detection does a quick RFB handshake to distinguish RealVNC (auth type 30) from other VNC servers, so the appropriate viewer is launched automatically.
