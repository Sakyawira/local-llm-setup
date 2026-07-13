#!/bin/bash
set -e

# WireGuard Client Setup Script
# Run this on a client Mac to connect to the Ollama server via WireGuard.
#
# Prerequisites:
#   - A client-*.conf file from the server (transferred via AirDrop/USB/scp)
#
# Usage:
#   ./setup-client.sh /path/to/client-macbook.conf
#   ./setup-client.sh  # prompts for conf file path

WG_DIR="$HOME/wireguard"
CONF_FILE="$1"

echo "============================================"
echo " WireGuard Client Setup (Ollama access)"
echo "============================================"
echo ""

# --- 1. Get conf file ---
if [ -z "$CONF_FILE" ]; then
    echo "No config file specified."
    echo "Enter the path to your client .conf file (from the server):"
    read -r CONF_FILE
fi

if [ ! -f "$CONF_FILE" ]; then
    echo "ERROR: File not found: $CONF_FILE"
    echo ""
    echo "You need a client-*.conf file from the Ollama server."
    echo "Ask the server admin to send it via AirDrop, USB, or scp."
    exit 1
fi

# --- 2. Install WireGuard ---
echo "[1/4] Installing WireGuard..."
if ! command -v brew &>/dev/null; then
    echo "ERROR: Homebrew is required. Install from https://brew.sh"
    exit 1
fi

if command -v wg &>/dev/null; then
    echo "  ✓ wireguard-tools already installed"
else
    echo "  Installing wireguard-tools..."
    brew install wireguard-tools
fi

# --- 3. Copy conf to wireguard directory ---
echo ""
echo "[2/4] Setting up config..."
mkdir -p "$WG_DIR"
DEST="$WG_DIR/client.conf"
cp "$CONF_FILE" "$DEST"
chmod 600 "$DEST"
echo "  ✓ Config copied to $DEST"

# Extract server WireGuard IP from AllowedIPs in the conf
SERVER_WG_IP=$(grep -A5 '\[Peer\]' "$DEST" | grep AllowedIPs | head -1 | sed 's/.*= *//;s|/.*||')
if [ -z "$SERVER_WG_IP" ]; then
    SERVER_WG_IP="10.0.0.1"
fi
echo "  Server WireGuard IP: $SERVER_WG_IP"

# --- 4. Create connect/disconnect scripts ---
echo ""
echo "[3/4] Creating connect/disconnect scripts..."

cat > "$WG_DIR/connect.sh" << CONNECTEOF
#!/bin/bash
set -e
echo "Connecting to WireGuard..."
sudo wg-quick up "$WG_DIR/client.conf"
echo ""
echo "Connected! Testing Ollama..."
if curl -s --connect-timeout 5 http://${SERVER_WG_IP}:11434/ | grep -q "running"; then
    echo "✓ Ollama is reachable at http://${SERVER_WG_IP}:11434"
else
    echo "⚠ WireGuard is up but Ollama didn't respond."
    echo "  Make sure the server is running: ~/wireguard/start.sh"
fi
CONNECTEOF

cat > "$WG_DIR/disconnect.sh" << DISCONNECTEOF
#!/bin/bash
echo "Disconnecting from WireGuard..."
sudo wg-quick down "$WG_DIR/client.conf" 2>/dev/null && echo "Disconnected." || echo "Was not connected."
DISCONNECTEOF

chmod +x "$WG_DIR/connect.sh" "$WG_DIR/disconnect.sh"
echo "  ✓ connect.sh created"
echo "  ✓ disconnect.sh created"

# --- 5. Set up shell alias for remote Ollama CLI ---
echo ""
echo "[4/4] Configuring shell..."

ZSHRC="$HOME/.zshrc"
EXPORT_LINE="export OLLAMA_HOST=http://${SERVER_WG_IP}:11434"

if [ -f "$ZSHRC" ] && grep -q "OLLAMA_HOST" "$ZSHRC"; then
    echo "  ⚠ OLLAMA_HOST already set in .zshrc, skipping"
else
    echo "" >> "$ZSHRC"
    echo "# Remote Ollama via WireGuard" >> "$ZSHRC"
    echo "$EXPORT_LINE" >> "$ZSHRC"
    echo "  ✓ Added OLLAMA_HOST to ~/.zshrc"
fi

# --- Summary ---
echo ""
echo "============================================"
echo " Setup Complete!"
echo "============================================"
echo ""
echo "Usage:"
echo "  ~/wireguard/connect.sh       # connect to Ollama server"
echo "  ~/wireguard/disconnect.sh    # disconnect"
echo ""
echo "Once connected:"
echo "  curl http://${SERVER_WG_IP}:11434/    # test API"
echo "  ollama list                            # list models (after: source ~/.zshrc)"
echo "  ollama run qwen2.5-coder:32b           # chat with a model"
echo ""
echo "For Cline (VS Code):"
echo "  API Provider: Ollama"
echo "  ✓ Use custom base URL: http://${SERVER_WG_IP}:11434"
echo "  Request Timeout: 120000"
echo ""
echo "For Open WebUI or other apps:"
echo "  Ollama API URL: http://${SERVER_WG_IP}:11434"
