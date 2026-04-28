#!/bin/bash
# ============================================================
# GitHub Webhook Setup for Jenkins (WSL)
# ============================================================
#
# OPTION 1: ngrok (recommended for real webhooks)
# ------------------------------------------------
# 1. Sign up free: https://dashboard.ngrok.com/signup
# 2. Copy your auth token from the dashboard
# 3. Run: ngrok config add-authtoken YOUR_TOKEN_HERE
# 4. Run: ngrok http 8081
# 5. Copy the https://xxxx.ngrok-free.app URL
# 6. Go to GitHub repo → Settings → Webhooks → Add webhook
#    - Payload URL: https://xxxx.ngrok-free.app/github-webhook/
#    - Content type: application/json
#    - Events: Just the push event
# 7. Done! Every push triggers Jenkins automatically.
#
# Quick start (after auth):
#   ngrok http 8081 --log=stdout &
#   # Copy the Forwarding URL and add to GitHub webhook
#
# OPTION 2: SCM Polling (already configured)
# ------------------------------------------------
# Jenkins polls GitHub every 2 minutes automatically.
# No setup needed — already working.
#
# OPTION 3: git pushj alias (already configured)
# ------------------------------------------------
# Use 'git pushj' instead of 'git push' to auto-trigger.
# ============================================================

echo "=== Jenkins Webhook Setup ==="
echo ""

if command -v ngrok &>/dev/null; then
    echo "ngrok is installed: $(ngrok version)"
    
    # Check if auth is configured
    if ngrok config check 2>/dev/null; then
        echo "ngrok auth: configured"
        echo ""
        echo "Starting ngrok tunnel to Jenkins (port 8081)..."
        echo "Press Ctrl+C to stop"
        echo ""
        ngrok http 8081
    else
        echo "ngrok auth: NOT configured"
        echo ""
        echo "Steps:"
        echo "  1. Go to https://dashboard.ngrok.com/signup (free)"
        echo "  2. Copy your auth token"
        echo "  3. Run: ngrok config add-authtoken YOUR_TOKEN"
        echo "  4. Run this script again"
    fi
else
    echo "ngrok not installed. Install with:"
    echo "  curl -sSL https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz | sudo tar xzf - -C /usr/local/bin"
fi
