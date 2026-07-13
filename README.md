# Local LLM Setup

Securely expose [Ollama](https://ollama.com) on a Mac to other devices over [WireGuard](https://www.wireguard.com). Only devices with a valid WireGuard key can access the LLM — nothing is exposed on the LAN.

## Architecture

```
┌─────────────────────────────────────────────┐
│  Server Mac (Ollama host)                   │
│                                             │
│  ollama (127.0.0.1:11434)                   │
│       ↑                                     │
│  socat (10.0.0.1:11434 → 127.0.0.1:11434)  │
│       ↑                                     │
│  WireGuard tunnel (10.0.0.1/24, UDP 51820) │
└─────────────────────────────────────────────┘
        ↕ encrypted tunnel
┌───────────────────────┐
│  Client (10.0.0.x)    │
│  Cline / Open WebUI   │
│  → http://10.0.0.1:11434
└───────────────────────┘
```

- Ollama binds to `127.0.0.1` only — not exposed on LAN
- `socat` forwards from the WireGuard interface (`10.0.0.1`) to localhost
- Only devices with a valid WireGuard private key can reach `10.0.0.1`

## Prerequisites

- macOS with [Homebrew](https://brew.sh)
- The scripts install everything else automatically (`wireguard-tools`, `socat`, `qrencode`, `ollama`)

## Quick Start (Server)

```bash
git clone <this-repo> && cd local-llm-setup

# Set up WireGuard + Ollama (generates keys, configs, start/stop scripts)
./setup-server.sh

# Or specify custom client names:
./setup-server.sh android ipad macbook2

# Start everything
~/wireguard/start.sh

# Pull a model
ollama pull qwen2.5-coder:32b
```

## Quick Start (Client Mac)

1. Get your `client-*.conf` file from the server (AirDrop, USB, scp — **never send over untrusted channels**)
2. Run:
   ```bash
   ./setup-client.sh /path/to/client-macbook.conf
   ```
3. Connect:
   ```bash
   ~/wireguard/connect.sh
   ```

## Quick Start (Windows / Android)

### Windows
1. Install [WireGuard for Windows](https://www.wireguard.com/install/)
2. Import the `client-windows.conf` file
3. Activate the tunnel
4. Access Ollama at `http://10.0.0.1:11434`

### Android
1. Install WireGuard from Play Store
2. Scan QR code (generate with `qrencode -t ansiutf8 < ~/wireguard/client-android.conf`)
3. Activate the tunnel
4. Access Ollama at `http://10.0.0.1:11434`

## Using with Cline (VS Code)

In Cline settings:
- **API Provider:** Ollama
- **Use custom base URL:** `http://10.0.0.1:11434`
- **Model:** pick a pulled model (e.g. `qwen2.5-coder:32b`)
- **Request Timeout:** `120000` ms

## Scripts

| Script | Purpose |
|--------|---------|
| `setup-server.sh` | Full server setup: install deps, generate keys/configs, create start/stop scripts |
| `setup-client.sh` | Client Mac setup: install WireGuard, import config, create connect/disconnect scripts |
| `start.sh` | Start WireGuard + Ollama + socat (server) |
| `stop.sh` | Stop everything (server) |

## Adding a New Device

On the server:

```bash
cd ~/wireguard

# Generate keys
wg genkey > newdevice_private.key
wg pubkey < newdevice_private.key > newdevice_public.key

# Add peer to wg0.conf with the next available IP (10.0.0.N/32)
# Create a client-newdevice.conf with the matching config
# Restart WireGuard:
~/wireguard/stop.sh && ~/wireguard/start.sh
```

## Security

- **No secrets in this repo** — keys and configs are generated at runtime and excluded via `.gitignore`
- **WireGuard** uses Curve25519 key exchange, ChaCha20-Poly1305 encryption, and silently drops unauthenticated packets
- **Ollama** never listens on the LAN — only on `127.0.0.1` with `socat` forwarding from the WireGuard interface
- **File permissions** are set to `600` (owner-only) for all keys and configs via `umask 077`
- **Port numbers** (`51820`, `11434`) are well-known defaults — security comes from cryptographic keys, not port obscurity

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Can't curl `10.0.0.1` from the server Mac | Expected — macOS can't route to its own WireGuard IP. Use `127.0.0.1` locally. |
| `wg-quick up` permission denied | Needs `sudo` |
| Client connects but can't reach Ollama | Check socat is running: `lsof -i :11434 -P -n \| grep LISTEN` |
| Endpoint unreachable | Server LAN IP probably changed (DHCP). Update `Endpoint` in client config. |
| Slow responses | Normal for local models. Increase Cline timeout to 120-180s or use a smaller model. |
