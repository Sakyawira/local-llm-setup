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
