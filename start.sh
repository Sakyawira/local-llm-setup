#!/bin/bash
set -e

WG_DIR="$HOME/wireguard"
WG_CONF="$WG_DIR/wg0.conf"
WG_IP="10.0.0.1"
WG_PORT="51820"
OLLAMA_PORT="11434"

LAN_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)
if [ -n "$LAN_IP" ]; then
	CLIENT_ENDPOINT="${LAN_IP}:${WG_PORT}"
	for conf in "$WG_DIR"/client-*.conf; do
		[ -f "$conf" ] || continue

		CURRENT_ENDPOINT=$(grep '^Endpoint = ' "$conf" | sed 's/^Endpoint = //')
		if [ "$CURRENT_ENDPOINT" != "$CLIENT_ENDPOINT" ]; then
			tmp_file=$(mktemp)
			awk -v endpoint="$CLIENT_ENDPOINT" '
				/^Endpoint = / { print "Endpoint = " endpoint; next }
				{ print }
			' "$conf" > "$tmp_file"
			chmod 600 "$tmp_file"
			mv "$tmp_file" "$conf"
			echo "Updated $(basename "$conf") endpoint to $CLIENT_ENDPOINT"
		fi
	done
else
	echo "Warning: could not detect LAN IP; client endpoints were not refreshed"
fi

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
