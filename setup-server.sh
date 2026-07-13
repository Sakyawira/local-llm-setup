#!/bin/bash
set -e

# WireGuard + Ollama Server Setup Script
# Run this on a fresh Mac to set up everything from scratch.
# Usage: ./setup-server.sh [client_names...]
# Example: ./setup-server.sh android windows macbook
# If no clients specified, defaults to: android windows macbook

WG_DIR="$HOME/wireguard"
WG_SUBNET="10.0.0"
WG_PORT="51820"
OLLAMA_PORT="11434"

# Client names from args, or defaults
if [ $# -gt 0 ]; then
    CLIENTS=("$@")
else
    CLIENTS=("android" "windows" "macbook")
fi

echo "============================================"
echo " WireGuard + Ollama Server Setup"
echo "============================================"
echo ""
echo "Server IP will be: ${WG_SUBNET}.1"
echo "Clients: ${CLIENTS[*]}"
echo ""

# --- 1. Install dependencies ---
echo "[1/6] Installing dependencies..."
if ! command -v brew &>/dev/null; then
    echo "ERROR: Homebrew is required. Install from https://brew.sh"
    exit 1
fi

for pkg in wireguard-tools socat qrencode ollama; do
    if command -v "$pkg" &>/dev/null || brew list "$pkg" &>/dev/null 2>&1; then
        echo "  ✓ $pkg already installed"
    else
        echo "  Installing $pkg..."
        brew install "$pkg"
    fi
done

# Check ollama specifically (it's a cask, not a formula)
if ! command -v ollama &>/dev/null; then
    echo "  Installing Ollama..."
    brew install --cask ollama
fi

# --- 2. Create wireguard directory ---
echo ""
echo "[2/6] Setting up $WG_DIR..."
mkdir -p "$WG_DIR"
cd "$WG_DIR"

# --- 3. Generate keys ---
echo ""
echo "[3/6] Generating keys..."

# Server keypair
if [ -f server_private.key ]; then
    echo "  ⚠ Server keys already exist, skipping (delete them to regenerate)"
else
    wg genkey | tee server_private.key | wg pubkey > server_public.key
    chmod 600 server_private.key
    echo "  ✓ Server keypair generated"
fi

SERVER_PRIVATE=$(cat server_private.key)
SERVER_PUBLIC=$(cat server_public.key)

# Client keypairs
for client in "${CLIENTS[@]}"; do
    if [ -f "${client}_private.key" ]; then
        echo "  ⚠ ${client} keys already exist, skipping"
    else
        wg genkey | tee "${client}_private.key" | wg pubkey > "${client}_public.key"
        chmod 600 "${client}_private.key"
        echo "  ✓ ${client} keypair generated"
    fi
done

# --- 4. Get LAN IP ---
echo ""
echo "[4/6] Detecting LAN IP..."
LAN_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "UNKNOWN")
if [ "$LAN_IP" = "UNKNOWN" ]; then
    echo "  ⚠ Could not detect LAN IP. You'll need to set Endpoint manually in client configs."
else
    echo "  ✓ LAN IP: $LAN_IP"
fi

# --- 5. Create configs ---
echo ""
echo "[5/6] Creating configs..."

# Server config
if [ -f wg0.conf ]; then
    echo "  ⚠ wg0.conf already exists, skipping (delete to regenerate)"
else
    {
        echo "[Interface]"
        echo "PrivateKey = $SERVER_PRIVATE"
        echo "Address = ${WG_SUBNET}.1/24"
        echo "ListenPort = $WG_PORT"

        i=2
        for client in "${CLIENTS[@]}"; do
            CLIENT_PUBLIC=$(cat "${client}_public.key")
            echo ""
            echo "# ${client}"
            echo "[Peer]"
            echo "PublicKey = $CLIENT_PUBLIC"
            echo "AllowedIPs = ${WG_SUBNET}.${i}/32"
            i=$((i + 1))
        done
    } > wg0.conf
    chmod 600 wg0.conf
    echo "  ✓ wg0.conf created"
fi

# Client configs
i=2
for client in "${CLIENTS[@]}"; do
    CONF_FILE="client-${client}.conf"
    if [ -f "$CONF_FILE" ]; then
        echo "  ⚠ $CONF_FILE already exists, skipping"
    else
        CLIENT_PRIVATE=$(cat "${client}_private.key")
        {
            echo "[Interface]"
            echo "PrivateKey = $CLIENT_PRIVATE"
            echo "Address = ${WG_SUBNET}.${i}/24"
            echo "DNS = 1.1.1.1"
            echo ""
            echo "[Peer]"
            echo "PublicKey = $SERVER_PUBLIC"
            echo "Endpoint = ${LAN_IP}:${WG_PORT}"
            echo "AllowedIPs = ${WG_SUBNET}.1/32"
            echo "PersistentKeepalive = 25"
        } > "$CONF_FILE"
        chmod 600 "$CONF_FILE"
        echo "  ✓ $CONF_FILE created (IP: ${WG_SUBNET}.${i})"
    fi
    i=$((i + 1))
done

# --- 6. Create start/stop scripts ---
echo ""
echo "[6/6] Creating start/stop scripts..."

cat > start.sh << 'STARTEOF'
#!/bin/bash
set -e

WG_CONF="$HOME/wireguard/wg0.conf"
WG_IP="10.0.0.1"
OLLAMA_PORT="11434"

echo "Starting WireGuard..."
sudo wg-quick up "$WG_CONF"

echo "Starting Ollama..."
ollama serve &
sleep 2

echo "Starting socat forwarder ($WG_IP:$OLLAMA_PORT → 127.0.0.1:$OLLAMA_PORT)..."
socat TCP-LISTEN:$OLLAMA_PORT,bind=$WG_IP,reuseaddr,fork TCP:127.0.0.1:$OLLAMA_PORT &

echo ""
echo "All services running:"
lsof -i :$OLLAMA_PORT -P -n 2>/dev/null | grep LISTEN
echo ""
echo "Ollama accessible at http://$WG_IP:$OLLAMA_PORT via WireGuard"
echo "Local access at http://127.0.0.1:$OLLAMA_PORT"
STARTEOF

cat > stop.sh << 'STOPEOF'
#!/bin/bash

echo "Stopping socat..."
pkill -f "socat.*10.0.0.1.*11434" 2>/dev/null && echo "  socat stopped" || echo "  socat was not running"

echo "Stopping WireGuard..."
sudo wg-quick down "$HOME/wireguard/wg0.conf" 2>/dev/null && echo "  WireGuard stopped" || echo "  WireGuard was not running"

echo "Stopping Ollama..."
pkill ollama 2>/dev/null && echo "  Ollama stopped" || echo "  Ollama was not running"

echo "All services stopped."
STOPEOF

chmod +x start.sh stop.sh
echo "  ✓ start.sh created"
echo "  ✓ stop.sh created"

# --- Summary ---
echo ""
echo "============================================"
echo " Setup Complete!"
echo "============================================"
echo ""
echo "Server: ${WG_SUBNET}.1 (this Mac)"
echo "LAN IP: ${LAN_IP}"
echo ""
echo "Clients:"
i=2
for client in "${CLIENTS[@]}"; do
    echo "  ${client}: ${WG_SUBNET}.${i} → client-${client}.conf"
    i=$((i + 1))
done
echo ""
echo "Files created in $WG_DIR:"
ls -1 "$WG_DIR"
echo ""
echo "Next steps:"
echo "  1. Run: ~/wireguard/start.sh"
echo "  2. Pull a model: ollama pull qwen2.5-coder:32b"
echo "  3. Send client-*.conf files to your devices (AirDrop/USB — keep them secret!)"
echo "  4. Android? Run: qrencode -t ansiutf8 < ~/wireguard/client-android.conf"
echo ""
echo "To tear down: ~/wireguard/stop.sh"
