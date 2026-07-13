#!/bin/bash

echo "Stopping socat..."
pkill -f "socat.*10.0.0.1.*11434" 2>/dev/null && echo "  socat stopped" || echo "  socat was not running"

echo "Stopping WireGuard..."
sudo wg-quick down "$HOME/wireguard/wg0.conf" 2>/dev/null && echo "  WireGuard stopped" || echo "  WireGuard was not running"

echo "Stopping Ollama..."
pkill ollama 2>/dev/null && echo "  Ollama stopped" || echo "  Ollama was not running"

echo "All services stopped."
